import Foundation
import os

/// Phần đầu của một lần quét đã lưu (đọc được mà không cần giải nén phần thân).
public struct SnapshotInfo: Sendable, Hashable {
    public let filePath: String
    public let rootPath: String
    public let scannedAt: Date
    public let appVersion: String
    public let totalSize: Int64
    public let fileCount: Int64
    public let dirCount: Int64
    /// Số thư mục đã lưu, kể cả thư mục gốc.
    public let nodeCount: Int
    /// Số thư mục không đọc được trong lần quét đó.
    public let errors: Int
}

/// Lưu cây thư mục sau mỗi lần quét xong để so sánh về sau. Chỉ có thư mục, không có từng file:
/// tên, dung lượng, số file, số thư mục con. Nằm ở ~/Library/Application Support/Diskat/snapshots/<thư mục gốc>/,
/// không gửi đi đâu.
///
/// Định dạng, phiên bản 1 (little-endian; không cần đọc được file của bản Windows):
///   "DSNP" | int32 phiên bản | phiên bản app | đường dẫn gốc | int64 lúc quét (mili giây kể từ 1970)
///   | int64 dung lượng, số file, số thư mục của gốc | int32 số thư mục | int32 số thư mục lỗi
///   (chuỗi ở phần đầu: int32 độ dài + UTF-8)
///   | phần thân nén LZFSE tới hết file: mọi thư mục theo chiều rộng (BFS), mỗi thư mục gồm
///     tên (varint độ dài + UTF-8, gốc để trống) | dung lượng, số file, số thư mục (varint) | cờ (byte) | số thư mục con (varint)
/// Duyệt theo chiều rộng nên các con của một thư mục nằm liền nhau: đọc lại thành mảng, không cần lưu con trỏ.
public enum ScanSnapshot {
    static let formatVersion: Int32 = 1
    /// Số lần quét giữ lại cho mỗi thư mục gốc (cũ hơn thì xóa).
    public static let keepPerRoot = 10
    static let fileExtension = ".dsnap"
    static let tmpExtension = ".dsnap.tmp"
    private static let magic: [UInt8] = Array("DSNP".utf8)

    static let flagUnreadable: UInt8 = 1, flagMount: UInt8 = 2, flagNotScanned: UInt8 = 4

    /// Độ dài tối đa của mỗi chuỗi ở phần đầu (phiên bản app, đường dẫn gốc).
    static let maxStringBytes = 4096
    /// Phần đầu luôn nằm gọn trong chừng này byte đầu file.
    private static let headerReadLimit = 16 * 1024
    /// File hỏng không được làm cấp phát quá lớn khi đọc.
    static let maxNodes = 200_000_000

    private static let base = OSAllocatedUnfairLock(initialState: defaultBaseFolder())

    /// Thư mục chứa mọi lần quét đã lưu (test đổi sang thư mục tạm).
    public static var baseFolder: String {
        get { base.withLock { $0 } }
        set { base.withLock { $0 = newValue } }
    }

    private static func defaultBaseFolder() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Library/Application Support"
        return support + "/Diskat/snapshots"
    }

    public static func normalize(_ path: String) -> String {
        FileOps.resolvedPath(path)
    }

    public static func sameRoot(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    /// Thư mục chứa các lần quét của một thư mục gốc: tên dễ nhận ra cộng mã băm của đường dẫn.
    public static func folder(for rootPath: String) -> String {
        let norm = normalize(rootPath)
        var label = ""
        if norm == "/" {
            label = "root"
        } else {
            for ch in (norm as NSString).lastPathComponent.prefix(32) {
                label.append((ch.isASCII && (ch.isLetter || ch.isNumber)) || ch == "-" || ch == "_" ? ch : "_")
            }
        }
        let hex = String(nameHash(norm.utf8), radix: 16)
        return FileOps.join(baseFolder, label + "-" + String(repeating: "0", count: 16 - hex.count) + hex)
    }

    /// FNV-1a 64 bit trên các byte UTF-8. Phân biệt hoa thường: APFS trả về tên giống nhau giữa các lần quét.
    static func nameHash<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in bytes {
            h ^= UInt64(b)
            h &*= 1_099_511_628_211
        }
        return h
    }

    /// Mili giây kể từ 1970, dùng cho cả phần đầu lẫn tên file.
    static func milliseconds(_ date: Date) -> Int64 {
        let ms = (date.timeIntervalSince1970 * 1000).rounded()
        // Ngày không hợp lệ (vô hạn, NaN, quá xa): coi như 1970
        return ms.isFinite && abs(ms) < 1e15 ? Int64(ms) : 0
    }

    /// Tên file theo thời điểm quét (UTC), dạng yyyyMMdd-HHmmss-SSS: sắp theo tên là sắp theo thời gian.
    static func fileName(_ ms: Int64) -> String {
        let secs = ms >= 0 ? ms / 1000 : (ms - 999) / 1000
        var t = time_t(secs)
        var parts = tm()
        gmtime_r(&t, &parts)
        return String(format: "%04d%02d%02d-%02d%02d%02d-%03d", parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday,
                      parts.tm_hour, parts.tm_min, parts.tm_sec, Int32(ms - secs * 1000))
    }

    // ================= Ghi =================

    /// Lưu cây vừa quét xong (gọi được ở luồng nền) rồi xóa bớt các lần quét cũ của cùng thư mục gốc.
    /// Ghi ra file tạm rồi đổi tên, nên app bị đóng giữa chừng cũng không để lại file hỏng.
    @discardableResult
    public static func save(_ root: DirNode, scannedAt: Date, errors: Int, appVersion: String,
                            keep: Int = keepPerRoot) throws -> SnapshotInfo {
        let rootPath = normalize(root.fullPath)
        guard rootPath.utf8.count <= maxStringBytes, appVersion.utf8.count <= maxStringBytes else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dir = folder(for: rootPath)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let ms = milliseconds(scannedAt)
        let path = FileOps.join(dir, fileName(ms) + fileExtension)
        let tmp = path + ".tmp"

        // Tổng của gốc đọc một lần: phần đầu và bản ghi của gốc trong phần thân khớp nhau
        let size = max(0, root.size), files = max(0, root.fileCount), dirs = max(0, root.dirCount)
        var body = ByteWriter()
        var count = 0
        var queue: [DirNode] = [root]
        var head = 0
        while head < queue.count {
            let n = queue[head]
            head += 1
            // Đọc danh sách con một lần: số con ghi ra và các con xếp hàng phải khớp nhau
            // kể cả khi giao diện vừa xóa / quét lại một thư mục
            let kids = n.children
            let isRoot = count == 0
            body.name(isRoot ? "" : n.name)
            body.varint(UInt64(isRoot ? size : max(0, n.size)))
            body.varint(UInt64(isRoot ? files : max(0, n.fileCount)))
            body.varint(UInt64(isRoot ? dirs : max(0, n.dirCount)))
            var flags: UInt8 = 0
            if n.isAccessDenied { flags |= flagUnreadable }
            if n.isMount { flags |= flagMount }
            if !n.isScanned { flags |= flagNotScanned }
            body.byte(flags)
            body.varint(UInt64(kids.count))
            queue.append(contentsOf: kids)
            count += 1
            // Bỏ phần đã xử lý ở đầu hàng đợi cho đỡ tốn bộ nhớ với cây rất lớn
            if head >= 1 << 16 && head * 2 >= queue.count {
                queue.removeFirst(head)
                head = 0
            }
        }
        guard count <= Int(Int32.max) else { throw CocoaError(.fileWriteUnknown) }

        var header = ByteWriter()
        header.bytes.append(contentsOf: magic)
        header.int32(formatVersion)
        header.string(appVersion)
        header.string(rootPath)
        header.int64(ms)
        header.int64(size)
        header.int64(files)
        header.int64(dirs)
        header.int32(Int32(count))
        header.int32(Int32(clamping: max(0, errors)))

        let packed = try (Data(body.bytes) as NSData).compressed(using: .lzfse) as Data
        var data = Data(header.bytes)
        data.append(packed)
        do {
            try data.write(to: URL(fileURLWithPath: tmp))
            if rename(tmp, path) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(atPath: tmp)
            throw error
        }
        prune(dir, keep: keep)
        return SnapshotInfo(filePath: path, rootPath: rootPath, scannedAt: Date(timeIntervalSince1970: Double(ms) / 1000),
                            appVersion: appVersion, totalSize: size, fileCount: files, dirCount: dirs,
                            nodeCount: count, errors: max(0, errors))
    }

    /// Giữ `keep` lần quét mới nhất (tên file là thời điểm quét nên sắp theo tên là đủ).
    private static func prune(_ dir: String, keep: Int) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        // Luôn giữ ít nhất một lần quét: lần vừa lưu
        for name in names.filter({ $0.hasSuffix(fileExtension) }).sorted(by: >).dropFirst(max(1, keep)) {
            try? fm.removeItem(atPath: FileOps.join(dir, name))
        }
        // File tạm sót lại khi app bị đóng lúc đang lưu
        let stale = Date().timeIntervalSince1970 - 3600
        for name in names where name.hasSuffix(tmpExtension) {
            let path = FileOps.join(dir, name)
            if let t = FileOps.modificationTime(path), t < stale {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    // ================= Đọc =================

    /// Các lần quét đã lưu của thư mục gốc này, mới nhất trước.
    public static func list(_ rootPath: String) -> [SnapshotInfo] {
        let norm = normalize(rootPath)
        let dir = folder(for: norm)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var result: [SnapshotInfo] = []
        for name in names where name.hasSuffix(fileExtension) {
            // Hai đường dẫn khác nhau có thể trùng mã băm: kiểm tra lại đường dẫn gốc đã lưu
            if let info = readInfo(FileOps.join(dir, name)), normalize(info.rootPath) == norm {
                result.append(info)
            }
        }
        result.sort { $0.scannedAt != $1.scannedAt ? $0.scannedAt > $1.scannedAt : $0.filePath > $1.filePath }
        return result
    }

    /// Đọc phần đầu của một file đã lưu; nil nếu file hỏng hoặc thuộc phiên bản định dạng khác.
    public static func readInfo(_ file: String) -> SnapshotInfo? {
        guard let handle = FileHandle(forReadingAtPath: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headerReadLimit),
              let header = try? parseHeader(head, file: file),
              let total = try? handle.seekToEnd(),
              total > UInt64(header.length) else { return nil }
        return header.info
    }

    /// Đọc phần đầu; trả về thông tin và độ dài phần đầu (phần thân nén bắt đầu ngay sau đó).
    static func parseHeader(_ data: Data, file: String) throws -> (info: SnapshotInfo, length: Int) {
        try data.withUnsafeBytes { raw in
            var r = ByteReader(raw)
            guard try r.bytes(4).elementsEqual(magic) else { throw ByteReader.Corrupt() }
            // Phiên bản định dạng khác (từ bản Diskat sau này): bỏ qua thay vì đọc sai
            guard try r.int32() == formatVersion else { throw ByteReader.Corrupt() }
            let version = try r.string()
            let root = try r.string()
            let ms = try r.int64()
            let size = try r.int64()
            let files = try r.int64()
            let dirs = try r.int64()
            let count = try r.int32()
            let errors = try r.int32()
            guard count > 0, Int(count) <= maxNodes, errors >= 0, !root.isEmpty else { throw ByteReader.Corrupt() }
            let info = SnapshotInfo(filePath: file, rootPath: root, scannedAt: Date(timeIntervalSince1970: Double(ms) / 1000),
                                    appVersion: version, totalSize: size, fileCount: files, dirCount: dirs,
                                    nodeCount: Int(count), errors: Int(errors))
            return (info, r.pos)
        }
    }

    /// Tổng số lần quét đã lưu (mọi thư mục gốc) và dung lượng chúng chiếm.
    public static func usage() -> (count: Int, bytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        for f in storedFiles() where f.path.hasSuffix(fileExtension) {
            count += 1
            bytes += f.size
        }
        return (count, bytes)
    }

    /// Xóa mọi lần quét đã lưu. Trả về số file đã xóa.
    @discardableResult
    public static func deleteAll() -> Int {
        var n = 0
        for f in storedFiles() {
            let name = (f.path as NSString).lastPathComponent
            // Chỉ xóa file do Diskat tạo, cộng .DS_Store của Finder để xóa được thư mục
            guard name.hasSuffix(fileExtension) || name.hasSuffix(tmpExtension) || name == ".DS_Store" else { continue }
            if unlink(f.path) == 0 && name.hasSuffix(fileExtension) { n += 1 }
        }
        let base = baseFolder
        for d in (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? [] {
            _ = rmdir(FileOps.join(base, d)) // chỉ xóa được thư mục đã rỗng
        }
        return n
    }

    /// Mọi file thường trong thư mục lưu (kể cả thư mục con), kèm kích thước.
    private static func storedFiles() -> [(path: String, size: Int64)] {
        let base = baseFolder
        guard FileOps.isDirectory(base), let e = FileManager.default.enumerator(atPath: base) else { return [] }
        var result: [(path: String, size: Int64)] = []
        for case let rel as String in e {
            let path = FileOps.join(base, rel)
            var st = stat()
            if lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG {
                result.append((path, Int64(st.st_size)))
            }
        }
        return result
    }
}

/// So cây đang hiển thị với một lần quét đã lưu. Lần quét cũ được nạp thành các mảng gọn (khoảng 36 byte
/// mỗi thư mục, không giữ tên mà chỉ giữ mã băm tên), rồi mỗi thư mục hiện tại được dò theo tên từ gốc xuống,
/// chỉ khi cần (khi dòng đó hiện ra) và nhớ lại kết quả. Gọi được từ nhiều luồng.
public final class ScanComparison: @unchecked Sendable {
    public let info: SnapshotInfo
    public let root: DirNode

    private let sizes: [Int64]
    private let fileCounts: [Int64]
    // Con của thư mục i là các vị trí firstChild[i] ..< firstChild[i] + childCount[i]
    private let firstChild: [Int32]
    private let childCount: [Int32]
    // Trong khoảng con của mỗi thư mục: mã băm tên đã sắp xếp, và thư mục ứng với từng vị trí
    private let hashes: [UInt64]
    private let order: [Int32]
    /// Kết quả dò đã nhớ. Giữ luôn node: ObjectIdentifier của node đã giải phóng có thể bị dùng lại cho node khác.
    private let found = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: (node: DirNode, index: Int)]())

    private init(info: SnapshotInfo, root: DirNode, sizes: [Int64], fileCounts: [Int64], firstChild: [Int32],
                 childCount: [Int32], hashes: [UInt64], order: [Int32]) {
        self.info = info
        self.root = root
        self.sizes = sizes
        self.fileCounts = fileCounts
        self.firstChild = firstChild
        self.childCount = childCount
        self.hashes = hashes
        self.order = order
    }

    /// Nạp một lần quét đã lưu để so với cây có gốc `root`. Ném lỗi nếu file không đọc được hoặc bị hỏng.
    public static func load(_ file: String, root: DirNode) throws -> ScanComparison {
        let data = try Data(contentsOf: URL(fileURLWithPath: file), options: .mappedIfSafe)
        do {
            return try decode(data, file: file, root: root)
        } catch {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file])
        }
    }

    private static func decode(_ data: Data, file: String, root: DirNode) throws -> ScanComparison {
        let header = try ScanSnapshot.parseHeader(data, file: file)
        let n = header.info.nodeCount
        let body = try (data.subdata(in: header.length..<data.count) as NSData).decompressed(using: .lzfse) as Data
        // Mỗi thư mục chiếm ít nhất 6 byte: số thư mục ở phần đầu không thể lớn hơn
        guard n <= body.count / 6 else { throw ByteReader.Corrupt() }

        var sizes: [Int64] = [], fileCounts: [Int64] = []
        var firstChild: [Int32] = [], childCount: [Int32] = []
        var hashes: [UInt64] = [], order: [Int32] = []
        sizes.reserveCapacity(n)
        fileCounts.reserveCapacity(n)
        firstChild.reserveCapacity(n)
        childCount.reserveCapacity(n)
        hashes.reserveCapacity(n)
        order.reserveCapacity(n)

        try body.withUnsafeBytes { raw in
            var r = ByteReader(raw)
            var next = 1
            for i in 0..<n {
                let len = try r.count(max: r.remaining)
                try hashes.append(ScanSnapshot.nameHash(r.bytes(len)))
                order.append(Int32(i))
                try sizes.append(r.int64Varint())
                try fileCounts.append(r.int64Varint())
                _ = try r.varint() // số thư mục: chưa dùng khi so sánh
                _ = try r.byte()   // cờ
                let kids = try r.count(max: n - next)
                firstChild.append(Int32(next))
                childCount.append(Int32(kids))
                next += kids
            }
            guard next == n, r.remaining == 0 else { throw ByteReader.Corrupt() }
        }

        // Sắp mã băm trong từng khoảng con để tìm nhị phân
        var scratch: [(hash: UInt64, index: Int32)] = []
        for i in 0..<n where childCount[i] > 1 {
            let lo = Int(firstChild[i]), hi = lo + Int(childCount[i])
            scratch.removeAll(keepingCapacity: true)
            for j in lo..<hi { scratch.append((hashes[j], order[j])) }
            scratch.sort { $0.hash < $1.hash }
            for (k, e) in scratch.enumerated() {
                hashes[lo + k] = e.hash
                order[lo + k] = e.index
            }
        }
        return ScanComparison(info: header.info, root: root, sizes: sizes, fileCounts: fileCounts,
                              firstChild: firstChild, childCount: childCount, hashes: hashes, order: order)
    }

    /// Vị trí của thư mục trong lần quét cũ, -1 nếu khi đó chưa có (thư mục mới).
    public func index(of node: DirNode) -> Int {
        if node === root { return 0 }
        return found.withLockUnchecked { found in
            // Đi ngược lên tới gốc hoặc tới thư mục đã dò, rồi dò xuống theo tên
            var chain: [DirNode] = []
            var idx = -1
            var reached = false
            var cur: DirNode? = node
            while let n = cur {
                if n === root {
                    idx = 0
                    reached = true
                    break
                }
                if let hit = found[ObjectIdentifier(n)] {
                    idx = hit.index
                    reached = true
                    break
                }
                chain.append(n)
                cur = n.parent
            }
            // Không về tới gốc: node đã bị gỡ khỏi cây hoặc thuộc cây khác. Không nhớ kết quả này
            guard reached else { return -1 }
            for n in chain.reversed() {
                if idx >= 0 { idx = findChild(idx, ScanSnapshot.nameHash(n.name.utf8)) }
                found[ObjectIdentifier(n)] = (n, idx)
            }
            return idx
        }
    }

    private func findChild(_ parent: Int, _ hash: UInt64) -> Int {
        var lo = Int(firstChild[parent]), hi = lo + Int(childCount[parent]) - 1
        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            let h = hashes[mid]
            if h == hash { return Int(order[mid]) }
            if h < hash { lo = mid + 1 } else { hi = mid - 1 }
        }
        return -1
    }

    public func size(at index: Int) -> Int64 { sizes[index] }
    public func files(at index: Int) -> Int64 { fileCounts[index] }

    /// Dung lượng thay đổi so với lần quét cũ; thư mục mới thì là toàn bộ dung lượng của nó.
    public func sizeChange(_ node: DirNode) -> Int64 {
        let i = index(of: node)
        return node.size - (i >= 0 ? sizes[i] : 0)
    }
}

/// Bộ đệm ghi little-endian.
private struct ByteWriter {
    var bytes: [UInt8] = []

    mutating func byte(_ v: UInt8) { bytes.append(v) }
    mutating func int32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func int64(_ v: Int64) { withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) } }

    /// Số không âm, 7 bit mỗi byte (LEB128).
    mutating func varint(_ v: UInt64) {
        var v = v
        while v >= 0x80 {
            bytes.append(UInt8(truncatingIfNeeded: v) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
    }

    /// Chuỗi ở phần đầu: int32 độ dài + UTF-8.
    mutating func string(_ s: String) {
        int32(Int32(s.utf8.count))
        bytes.append(contentsOf: s.utf8)
    }

    /// Tên thư mục trong phần thân: varint độ dài + UTF-8.
    mutating func name(_ s: String) {
        varint(UInt64(s.utf8.count))
        bytes.append(contentsOf: s.utf8)
    }
}

/// Đọc tuần tự little-endian, luôn kiểm tra giới hạn: file hỏng thì ném lỗi chứ không đọc tràn.
private struct ByteReader {
    struct Corrupt: Error {}

    let buf: UnsafeRawBufferPointer
    var pos = 0

    init(_ buf: UnsafeRawBufferPointer) { self.buf = buf }

    var remaining: Int { buf.count - pos }

    mutating func bytes(_ n: Int) throws -> UnsafeRawBufferPointer {
        guard n >= 0, n <= remaining else { throw Corrupt() }
        defer { pos += n }
        return UnsafeRawBufferPointer(rebasing: buf[pos..<pos + n])
    }

    mutating func byte() throws -> UInt8 {
        guard pos < buf.count else { throw Corrupt() }
        defer { pos += 1 }
        return buf[pos]
    }

    mutating func int32() throws -> Int32 {
        try Int32(littleEndian: bytes(4).loadUnaligned(as: Int32.self))
    }

    mutating func int64() throws -> Int64 {
        try Int64(littleEndian: bytes(8).loadUnaligned(as: Int64.self))
    }

    mutating func varint() throws -> UInt64 {
        var v: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let b = try byte()
            // Byte thứ 10 chỉ còn chỗ cho 1 bit
            if shift == 63 && b > 1 { throw Corrupt() }
            v |= UInt64(b & 0x7F) << shift
            if b < 0x80 { return v }
            shift += 7
        }
    }

    mutating func int64Varint() throws -> Int64 {
        let v = try varint()
        guard v <= UInt64(Int64.max) else { throw Corrupt() }
        return Int64(v)
    }

    /// Số đếm không âm, không vượt quá `limit`.
    mutating func count(max limit: Int) throws -> Int {
        let v = try varint()
        guard v <= UInt64(Swift.max(0, limit)) else { throw Corrupt() }
        return Int(v)
    }

    /// Chuỗi ở phần đầu: int32 độ dài + UTF-8.
    mutating func string() throws -> String {
        let n = try int32()
        guard n >= 0, Int(n) <= ScanSnapshot.maxStringBytes else { throw Corrupt() }
        return try String(decoding: bytes(Int(n)), as: UTF8.self)
    }
}
