import CryptoKit
import Darwin
import Foundation
import os
import UniformTypeIdentifiers

/// Một file trong nhóm trùng lặp. Các tên khác của cùng một file (hard link) được gộp vào đây.
public final class DupFile: Sendable {
    public let path: String
    /// Lần sửa cuối (giây kể từ 1970).
    public let modified: Double
    /// Tổng số tên (hard link) của file trên ổ đĩa, kể cả các tên nằm ngoài thư mục quét.
    public let linkCount: Int
    /// Các tên khác của cùng file tìm thấy trong thư mục quét.
    public let otherNames: [String]
    /// Clone APFS (ví dụ bản "Nhân bản" của Finder): dùng chung khối dữ liệu với một bản khác trong nhóm
    /// (hoặc với một clone ở nơi khác trên ổ), nên xóa đi gần như không lấy lại được chỗ.
    public let isClone: Bool
    /// Xóa một tên của file có nhiều hard link không giải phóng được chỗ nào.
    public var isHardLinked: Bool { linkCount > 1 }

    /// Vùng dữ liệu trên đĩa: các file cùng (device, cloneID) khác 0 là clone của nhau.
    let device: Int32
    let cloneID: UInt64
    /// Số clone đầy đủ dùng chung dữ liệu này trên cả ổ, kể cả chính nó (0: ổ không cho biết).
    let cloneRefs: UInt32

    init(path: String, modified: Double, linkCount: Int, otherNames: [String], isClone: Bool,
         device: Int32 = 0, cloneID: UInt64 = 0, cloneRefs: UInt32 = 0) {
        self.path = path
        self.modified = modified
        self.linkCount = linkCount
        self.otherNames = otherNames
        self.isClone = isClone
        self.device = device
        self.cloneID = cloneID
        self.cloneRefs = cloneRefs
    }
}

public final class DupGroup: Sendable {
    public let size: Int64
    /// Mới sửa nhất trước.
    public let files: [DupFile]
    /// Dung lượng giải phóng được khi chỉ giữ một bản (chỉ tính những bản xóa được;
    /// các clone APFS dùng chung một vùng dữ liệu tính là một bản).
    public let wasted: Int64

    /// Tính lại `wasted` từ các file (ví dụ sau khi giao diện bỏ những file đã xóa khỏi nhóm).
    public init(size: Int64, files: [DupFile]) {
        self.size = size
        self.files = files
        wasted = size * Int64(Self.freeableCopies(files))
    }

    private struct Storage: Hashable {
        let device: Int32
        let cloneID: UInt64
        /// Vị trí trong nhóm cho file không có clone id: mỗi file là một vùng riêng
        let index: Int
    }

    /// Số bản có thể xóa để lấy lại chỗ. Mỗi vùng dữ liệu (một file, hoặc các clone của nhau) chỉ
    /// được giải phóng khi xóa mọi tên của nó: không được có hard link, cũng không được có clone nằm ngoài nhóm.
    static func freeableCopies(_ files: [DupFile]) -> Int {
        var units: [Storage: (members: Int, refs: UInt32, pinned: Bool)] = [:]
        for (i, f) in files.enumerated() {
            let key = f.cloneID != 0 ? Storage(device: f.device, cloneID: f.cloneID, index: -1)
                                     : Storage(device: 0, cloneID: 0, index: i)
            var u = units[key] ?? (0, 0, false)
            u.members += 1
            u.refs = max(u.refs, f.cloneRefs)
            u.pinned = u.pinned || f.isHardLinked
            units[key] = u
        }
        let freeable = units.values.filter { !$0.pinned && Int($0.refs) <= $0.members }.count
        return max(0, min(units.count - 1, freeable))
    }
}

public struct DupResult: Sendable {
    /// Lãng phí nhiều nhất trước.
    public let groups: [DupGroup]
    /// Số file đủ lớn đã liệt kê.
    public let files: Int64
    /// File iCloud chưa tải về máy: không đọc để khỏi tải cả file về.
    public let cloudSkipped: Int64
    /// File không đọc được (không có quyền, bị xóa hoặc đang thay đổi trong lúc so).
    public let unreadable: Int64

    public init(groups: [DupGroup], files: Int64, cloudSkipped: Int64, unreadable: Int64) {
        self.groups = groups
        self.files = files
        self.cloudSkipped = cloudSkipped
        self.unreadable = unreadable
    }
}

/// Tìm file trùng nội dung trong cả cây thư mục: nhóm theo dung lượng, rồi so 64 KB đầu,
/// cuối cùng mới băm toàn bộ (SHA-256, phần cứng tăng tốc) những file vẫn còn giống nhau.
/// Không đọc file iCloud chưa tải về; nhiều tên của cùng một file (hard link) được tính là một file;
/// các clone APFS của nhau được đánh dấu vì xóa đi không lấy lại được chỗ.
public enum DuplicateFinder {
    public static let headSize = 64 * 1024
    private static let bufferSize = 1 << 20
    /// SSD đọc song song nhanh hơn; phần đầu file nhỏ nên dùng nhiều luồng hơn khi băm toàn bộ.
    private static let headThreads = 4
    private static let fullThreads = 2

    /// Tiến độ, giao diện đọc định kỳ từ luồng khác.
    public final class Progress: Sendable {
        private struct State {
            var stage = 0
            var found: Int64 = 0
            var done: Int64 = 0
            var total: Int64 = 0
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        public init() {}

        /// 0: liệt kê file, 1: so 64 KB đầu, 2: so toàn bộ nội dung.
        public var stage: Int {
            get { state.withLock { $0.stage } }
            set { state.withLock { $0.stage = newValue } }
        }

        /// Số file đủ lớn đã liệt kê.
        public var found: Int64 {
            get { state.withLock { $0.found } }
            set { state.withLock { $0.found = newValue } }
        }

        /// Bước 1: số file; bước 2: số byte.
        public var done: Int64 {
            get { state.withLock { $0.done } }
            set { state.withLock { $0.done = newValue } }
        }

        public var total: Int64 {
            get { state.withLock { $0.total } }
            set { state.withLock { $0.total = newValue } }
        }

        /// Sang bước mới: đặt lại số đã làm cùng lúc với tổng để giao diện không thấy số lẫn giữa hai bước.
        func begin(stage: Int, total: Int64) {
            state.withLock {
                if stage == 0 { $0.found = 0 }
                $0.done = 0
                $0.total = total
                $0.stage = stage
            }
        }

        func add(found n: Int64) { state.withLock { $0.found += n } }
        func add(done n: Int64) { state.withLock { $0.done += n } }
    }

    public final class CancelFlag: Sendable {
        private let flag = OSAllocatedUnfairLock(initialState: false)

        public init() {}

        public func cancel() { flag.withLock { $0 = true } }
        public var isCancelled: Bool { flag.withLock { $0 } }
    }

    /// Một file liệt kê được ở bước 0.
    private struct Listed {
        let path: String
        let size: Int64
        let modified: Double
    }

    /// File cần so (có ít nhất một file khác cùng dung lượng). Mỗi file chỉ do một luồng ghi,
    /// kết quả được đọc lại sau khi các luồng đã xong.
    private final class Entry: @unchecked Sendable {
        let path: String
        let size: Int64
        let modified: Double
        var ok = false
        /// Thành file iCloud chưa tải về sau khi liệt kê
        var cloud = false
        var device: Int32 = 0
        var inode: UInt64 = 0
        var links = 1
        var cloneID: UInt64 = 0
        var cloneRefs: UInt32 = 0
        var head: SHA256.Digest?
        /// Phần sau 64 KB đầu; nil với file không lớn hơn 64 KB
        var rest: SHA256.Digest?
        var others: [String] = []

        init(_ f: Listed) {
            path = f.path
            size = f.size
            modified = f.modified
        }
    }

    private struct FileKey: Hashable {
        let device: Int32
        let inode: UInt64
    }

    private struct HeadKey: Hashable {
        let size: Int64
        let head: SHA256.Digest
    }

    private struct CloneKey: Hashable {
        let device: Int32
        let cloneID: UInt64
    }

    /// Ném CancellationError khi bị hủy; ném POSIXError nếu không mở được chính thư mục gốc.
    public static func find(root: String, minSize: Int64, skipSystem: Bool, progress: Progress,
                            cancel: CancelFlag) throws -> DupResult {
        let minSize = max(1, minSize) // file rỗng giống nhau nhưng không tốn chỗ
        let rootPath = FileOps.resolvedPath(root)

        // ---- Bước 0: liệt kê, nhóm theo dung lượng ----
        progress.begin(stage: 0, total: 0)
        let walker = Walker(root: rootPath, minSize: minSize, rules: SkipRules(skipSystem: skipSystem),
                            progress: progress, cancel: cancel)
        walker.run(threads: max(2, min(8, ProcessInfo.processInfo.activeProcessorCount)))
        if cancel.isCancelled { throw CancellationError() }
        if walker.rootError != 0 { throw POSIXError(POSIXErrorCode(rawValue: walker.rootError) ?? .EIO) }
        let found = Int64(walker.files.count)
        var cloud = walker.cloud

        var heads: [Entry] = []
        do {
            var bySize: [Int64: [Listed]] = [:]
            for f in walker.files { bySize[f.size, default: []].append(f) }
            walker.files = []
            for list in bySize.values where list.count > 1 {
                for f in list { heads.append(Entry(f)) }
            }
        }

        // ---- Bước 1: mở các file cùng dung lượng, lấy mã file và băm 64 KB đầu ----
        // Đọc theo thứ tự đường dẫn: các file cùng thư mục thường nằm gần nhau trên ổ đĩa
        heads.sort { $0.path < $1.path }
        progress.begin(stage: 1, total: Int64(heads.count))
        try parallel(heads, threads: headThreads, bufferSize: headSize, cancel: cancel) { e, buf in
            readHead(e, buf)
            progress.add(done: 1)
        }

        // Gộp các tên của cùng một file (hard link), rồi nhóm theo (dung lượng, 64 KB đầu)
        var unreadable: Int64 = 0
        var seen: [FileKey: Entry] = [:]
        var byHead: [HeadKey: [Entry]] = [:]
        for e in heads {
            guard e.ok, let head = e.head else {
                if e.cloud { cloud += 1 } else { unreadable += 1 }
                continue
            }
            let key = FileKey(device: e.device, inode: e.inode)
            if let first = seen[key] {
                first.others.append(e.path)
                continue
            }
            seen[key] = e
            byHead[HeadKey(size: e.size, head: head), default: []].append(e)
        }
        seen = [:]
        heads = []
        let sameHead = byHead.values.filter { $0.count > 1 }
        byHead = [:]

        // ---- Bước 2: băm phần còn lại của những file vẫn giống nhau ----
        var full = sameHead.flatMap { $0 }.filter { $0.size > Int64(headSize) }
        full.sort { $0.path < $1.path }
        progress.begin(stage: 2, total: full.reduce(0) { $0 + $1.size - Int64(headSize) })
        try parallel(full, threads: fullThreads, bufferSize: bufferSize, cancel: cancel) { e, buf in
            hashRest(e, buf, progress, cancel)
        }
        unreadable += Int64(full.reduce(0) { $0 + ($1.ok ? 0 : 1) })

        // ---- Kết quả: nhóm theo toàn bộ nội dung, lãng phí nhiều nhất trước ----
        var groups: [DupGroup] = []
        for list in sameHead {
            for items in Dictionary(grouping: list.filter(\.ok), by: \.rest).values where items.count > 1 {
                // Clone APFS trong nhóm: cùng clone id trên cùng ổ là cùng một vùng dữ liệu
                var clones: [CloneKey: Int] = [:]
                for e in items where e.cloneID != 0 {
                    clones[CloneKey(device: e.device, cloneID: e.cloneID), default: 0] += 1
                }
                let files = items
                    .sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.path < $1.path }
                    .map { e in
                        let sharedInGroup = e.cloneID != 0
                            && clones[CloneKey(device: e.device, cloneID: e.cloneID), default: 0] > 1
                        return DupFile(path: e.path, modified: e.modified, linkCount: e.links,
                                       otherNames: e.others, isClone: sharedInGroup || e.cloneRefs > 1,
                                       device: e.device, cloneID: e.cloneID, cloneRefs: e.cloneRefs)
                    }
                // Bản nào cũng có hard link khác: xóa bản nào cũng không lấy lại được chỗ
                if files.allSatisfy(\.isHardLinked) { continue }
                groups.append(DupGroup(size: items[0].size, files: files))
            }
        }
        groups.sort { $0.wasted != $1.wasted ? $0.wasted > $1.wasted : $0.files[0].path < $1.files[0].path }
        return DupResult(groups: groups, files: found, cloudSkipped: cloud, unreadable: unreadable)
    }

    // ---------------- Liệt kê ----------------

    /// Thư mục không quét.
    private struct SkipRules: Sendable {
        /// Thùng rác, chỉ mục Spotlight, nhật ký sự kiện, bản lưu phiên bản tài liệu, file tạm của hệ thống
        static let alwaysSkipped: Set<String> = [
            ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems",
        ]
        private static let dataVolume = "/System/Volumes/Data"

        let skipSystem: Bool
        private let systemDirs: Set<String>

        init(skipSystem: Bool) {
            self.skipSystem = skipSystem
            systemDirs = skipSystem ? Self.systemFolders() : []
        }

        /// Hệ thống, ứng dụng, thư viện dùng chung, ~/Library: ứng dụng thường có file giống hệt nhau ở đây,
        /// xóa đi sẽ hỏng ứng dụng. Kèm cả đường dẫn qua ổ dữ liệu (/System/Volumes/Data/...).
        private static func systemFolders() -> Set<String> {
            var set: Set<String> = ["/System"]
            for dir in ["/Library", "/Applications", "/usr", "/bin", "/sbin", "/private", "/opt", "/cores"] {
                set.insert(dir)
                set.insert(dataVolume + dir)
            }
            let home = FileOps.resolvedPath(NSHomeDirectory())
            set.insert(home + "/Library")
            set.insert(dataVolume + home + "/Library")
            return set
        }

        func skips(name: String, path: String, parent: String) -> Bool {
            if Self.alwaysSkipped.contains(name) { return true }
            guard skipSystem else { return false }
            if systemDirs.contains(path) { return true }
            // Library của mọi tài khoản (/Users/<tên>/Library): dữ liệu và bản cài của ứng dụng
            if name == "Library" {
                let users = (parent as NSString).deletingLastPathComponent
                if users == "/Users" || users == Self.dataVolume + "/Users" { return true }
            }
            // Gói (.app, .framework, .photoslibrary...): Finder hiện như một file, bên trong là của ứng dụng
            return DuplicateFinder.isPackage(name)
        }
    }

    private static let packageCache = OSAllocatedUnfairLock(initialState: [String: Bool]())

    /// Thư mục có phần mở rộng là gói / bundle (theo UTType, nhớ kết quả theo phần mở rộng).
    static func isPackage(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        let ext = name[name.index(after: dot)...].lowercased()
        if ext.isEmpty { return false }
        if let known = packageCache.withLock({ $0[ext] }) { return known }
        // UTType(filenameExtension:) chỉ tìm loại dữ liệu (file), không thấy loại thư mục như .app
        let result = UTType.types(tag: ext, tagClass: .filenameExtension, conformingTo: nil)
            .contains { $0.conforms(to: .package) || $0.conforms(to: .bundle) }
        packageCache.withLock { $0[ext] = result }
        return result
    }

    /// Duyệt cây thư mục song song: các luồng cùng lấy thư mục từ một ngăn xếp chung (giống DiskScanner).
    /// Không đi theo symlink, không sang ổ khác (mount point), chỉ lấy file thường.
    private final class Walker: @unchecked Sendable {
        let root: String
        let minSize: Int64
        let rules: SkipRules
        let progress: Progress
        let cancel: CancelFlag

        private let cond = NSCondition()
        private var stack: [String]
        private var pending = 1
        private var finished = false
        /// Kết quả gộp từ các luồng; chỉ đọc sau khi `run` trả về.
        var files: [Listed] = []
        private(set) var cloud: Int64 = 0
        /// errno nếu không mở được thư mục gốc.
        private(set) var rootError: Int32 = 0

        init(root: String, minSize: Int64, rules: SkipRules, progress: Progress, cancel: CancelFlag) {
            self.root = root
            self.minSize = minSize
            self.rules = rules
            self.progress = progress
            self.cancel = cancel
            stack = [root]
        }

        func run(threads: Int) {
            DispatchQueue.concurrentPerform(iterations: threads) { _ in worker() }
        }

        private func worker() {
            let lister = DirLister()
            var files: [Listed] = []
            var cloud: Int64 = 0
            while true {
                cond.lock()
                while stack.isEmpty && !finished { cond.wait() }
                if finished {
                    self.files.append(contentsOf: files)
                    self.cloud += cloud
                    cond.unlock()
                    return
                }
                let dir = stack.removeLast()
                cond.unlock()

                let subdirs = cancel.isCancelled ? [] : list(dir, lister, &files, &cloud)

                cond.lock()
                if cancel.isCancelled {
                    stack.removeAll()
                    finished = true
                    cond.broadcast()
                } else if !subdirs.isEmpty {
                    // Đẩy ngược để thư mục đầu tiên được lấy ra trước (duyệt theo chiều sâu)
                    stack.append(contentsOf: subdirs.reversed())
                    pending += subdirs.count
                    cond.broadcast()
                }
                pending -= 1
                if pending == 0 {
                    finished = true
                    cond.broadcast()
                }
                cond.unlock()
            }
        }

        /// Liệt kê một thư mục; trả về các thư mục con cần duyệt tiếp.
        private func list(_ dir: String, _ lister: DirLister, _ files: inout [Listed], _ cloud: inout Int64) -> [String] {
            var subdirs: [String] = []
            var any = false
            let before = files.count
            let isVolumeRoot = dir == "/"
            let rc = lister.list(dir) { e in
                any = true
                if e.isDirectory {
                    if e.isMountPoint { return }
                    let name = e.name
                    if isVolumeRoot && DiskScanner.virtualRootDirs.contains(name) { return }
                    let path = FileOps.join(dir, name)
                    if !rules.skips(name: name, path: path, parent: dir) { subdirs.append(path) }
                    return
                }
                // Chỉ file thường: symlink, FIFO, socket... bị bỏ qua
                guard e.isRegularFile, e.dataLength >= minSize else { return }
                // Dữ liệu chỉ có trên iCloud: đọc vào sẽ tải cả file về
                if e.isDataless {
                    cloud += 1
                    return
                }
                files.append(Listed(path: FileOps.join(dir, e.name), size: e.dataLength, modified: e.modified))
            }
            if rc != 0 && !any && dir == root {
                cond.lock()
                rootError = rc
                cond.unlock()
            }
            if files.count > before { progress.add(found: Int64(files.count - before)) }
            return subdirs
        }
    }

    // ---------------- Đọc file ----------------

    /// Chạy `body` cho từng file trên `threads` luồng (lấy lần lượt theo thứ tự), mỗi luồng một bộ đệm.
    /// Trong lúc chạy, luồng không được tải file iCloud về: đọc một file "dataless" sẽ thất bại.
    private static func parallel(_ items: [Entry], threads: Int, bufferSize: Int, cancel: CancelFlag,
                                 _ body: (Entry, UnsafeMutableRawPointer) -> Void) throws {
        let next = OSAllocatedUnfairLock(initialState: 0)
        DispatchQueue.concurrentPerform(iterations: min(threads, items.count)) { _ in
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
            defer { buffer.deallocate() }
            let old = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
            setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                           IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
            // Trả lại như cũ: luồng của GCD còn được dùng cho việc khác
            defer {
                setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                               old >= 0 ? old : IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT)
            }
            while !cancel.isCancelled {
                let i = next.withLock { n -> Int in
                    defer { n += 1 }
                    return n
                }
                if i >= items.count { break }
                body(items[i], buffer)
            }
        }
        if cancel.isCancelled { throw CancellationError() }
    }

    /// O_NOFOLLOW: file bị thay bằng symlink sau khi liệt kê sẽ không bị đi theo.
    /// O_NONBLOCK: nếu bị thay bằng FIFO thì không bị treo chờ (không ảnh hưởng file thường).
    private static func openForReading(_ path: String) -> Int32 {
        open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    }

    private static func readHead(_ e: Entry, _ buffer: UnsafeMutableRawPointer) {
        let fd = openForReading(e.path)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return }
        if st.st_flags & UInt32(SF_DATALESS) != 0 {
            e.cloud = true
            return
        }
        // Dung lượng đã đổi so với lúc liệt kê: nội dung đang thay đổi, không coi là bản sao
        guard st.st_size == e.size else { return }
        e.device = st.st_dev
        e.inode = st.st_ino
        e.links = max(1, Int(st.st_nlink))

        let want = Int(min(Int64(headSize), e.size))
        var n = 0
        while n < want {
            let r = pread(fd, buffer + n, want - n, off_t(n))
            if r < 0 && errno == EINTR { continue }
            if r <= 0 { return } // file ngắn đi sau khi liệt kê, hoặc lỗi đọc
            n += r
        }
        var hash = SHA256()
        hash.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: n))
        e.head = hash.finalize()
        (e.cloneID, e.cloneRefs) = cloneInfo(fd)
        e.ok = true
    }

    private static func hashRest(_ e: Entry, _ buffer: UnsafeMutableRawPointer, _ progress: Progress,
                                 _ cancel: CancelFlag) {
        e.ok = false
        let fd = openForReading(e.path)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var st = stat()
        // Phải đúng file đã đọc phần đầu (không bị thay bằng file khác trong lúc chờ)
        guard fstat(fd, &st) == 0, st.st_dev == e.device, st.st_ino == e.inode else { return }

        var hash = SHA256()
        var offset = Int64(headSize)
        while offset < e.size {
            if cancel.isCancelled { return }
            let want = Int(min(Int64(bufferSize), e.size - offset))
            let r = pread(fd, buffer, want, off_t(offset))
            if r < 0 && errno == EINTR { continue }
            if r <= 0 { return } // file ngắn đi trong lúc đọc
            hash.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: r))
            offset += Int64(r)
            progress.add(done: Int64(r))
        }
        // File đã dài ra (hoặc ngắn đi) so với lúc liệt kê: nội dung đang thay đổi, không coi là bản sao
        guard fstat(fd, &st) == 0, st.st_size == e.size else { return }
        e.rest = hash.finalize()
        e.ok = true
    }

    /// Clone id và số clone của vùng dữ liệu (APFS). File là clone đầy đủ của nhau có cùng clone id;
    /// (0, 0) nếu ổ không hỗ trợ (HFS+, exFAT, ổ mạng...).
    private static func cloneInfo(_ fd: Int32) -> (id: UInt64, refs: UInt32) {
        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        // Với FSOPT_ATTR_CMN_EXTENDED, nhóm forkattr được hiểu là các thuộc tính ATTR_CMNEXT_*
        attrs.forkattr = attrgroup_t(ATTR_CMNEXT_CLONEID) | attrgroup_t(ATTR_CMNEXT_CLONE_REFCNT)
        var storage = (UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0))
        return withUnsafeMutableBytes(of: &storage) { buf -> (UInt64, UInt32) in
            guard let base = buf.baseAddress,
                  fgetattrlist(fd, &attrs, base, buf.count, UInt32(FSOPT_ATTR_CMN_EXTENDED)) == 0 else { return (0, 0) }
            // Độ dài, các thuộc tính trả về, rồi các thuộc tính theo thứ tự bit
            var field = base + 4
            let returned = field.loadUnaligned(as: attribute_set_t.self)
            field += MemoryLayout<attribute_set_t>.size
            var id: UInt64 = 0
            var refs: UInt32 = 0
            if returned.forkattr & attrgroup_t(ATTR_CMNEXT_CLONEID) != 0 {
                id = field.loadUnaligned(as: UInt64.self)
                field += 8
            }
            if returned.forkattr & attrgroup_t(ATTR_CMNEXT_CLONE_REFCNT) != 0 {
                refs = field.loadUnaligned(as: UInt32.self)
            }
            return (id, refs)
        }
    }
}
