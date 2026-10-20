import Foundation
import os
import Testing
@testable import DiskatCore

/// Thư mục lưu tạm cho một test: đổi `ScanSnapshot.baseFolder`, gọi `restore()` (trong defer) để trả lại.
final class TempSnapshots {
    let folder: String
    private let saved: String

    init() throws {
        saved = ScanSnapshot.baseFolder
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("diskat-snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        folder = FileOps.resolvedPath(base.path)
        ScanSnapshot.baseFolder = folder
    }

    func restore() {
        ScanSnapshot.baseFolder = saved
        try? FileManager.default.removeItem(atPath: folder)
    }
}

private func scan(_ path: String) async -> DirNode {
    let scanner = DiskScanner(path: path)
    await scanner.run()
    return scanner.root
}

private func child(_ node: DirNode, _ name: String) -> DirNode? {
    node.children.first { $0.name == name }
}

private func allNodes(_ root: DirNode) -> [DirNode] {
    var all = [root]
    var i = 0
    while i < all.count {
        all += all[i].children
        i += 1
    }
    return all
}

private func hex(_ path: String) -> String {
    String(format: "%016llx", ScanSnapshot.nameHash(ScanSnapshot.normalize(path).utf8))
}

private func patched(_ data: Data, at offset: Int, _ value: Int32) -> Data {
    var d = data
    withUnsafeBytes(of: value.littleEndian) { d.replaceSubrange(offset..<offset + 4, with: $0) }
    return d
}

// Cùng dùng ScanSnapshot.baseFolder nên chạy lần lượt
@Suite(.serialized) struct ScanSnapshotTests {
    @Test func saveReadAndList() async throws {
        let store = try TempSnapshots()
        defer { store.restore() }
        let t = try TempTree()
        try t.file("a/x.bin", bytes: 10_000)
        try t.file("a/b/y.bin", bytes: 20_000)
        try t.file("c/z.bin", bytes: 5_000)
        try t.dir("empty")
        let root = await scan(t.root)

        let when = Date(timeIntervalSince1970: 1_700_000_000.123)
        let info = try ScanSnapshot.save(root, scannedAt: when, errors: 2, appVersion: "1.2.3")
        #expect((info.filePath as NSString).lastPathComponent == "20231114-221320-123.dsnap")
        #expect((info.filePath as NSString).deletingLastPathComponent == ScanSnapshot.folder(for: t.root))
        #expect(!FileManager.default.fileExists(atPath: info.filePath + ".tmp"))
        #expect(info.rootPath == t.root)
        #expect(info.scannedAt == when)
        #expect(info.appVersion == "1.2.3")
        #expect(info.totalSize == root.size)
        #expect(info.fileCount == 3)
        #expect(info.dirCount == 4)
        #expect(info.nodeCount == 5)
        #expect(info.errors == 2)
        #expect(ScanSnapshot.readInfo(info.filePath) == info)

        let later = try ScanSnapshot.save(root, scannedAt: when.addingTimeInterval(60), errors: 0, appVersion: "1.2.4")
        #expect(ScanSnapshot.list(t.root) == [later, info])
        #expect(ScanSnapshot.list(t.root + "/") == [later, info])
        #expect(ScanSnapshot.list(t.root + "/a").isEmpty)

        // Cây không đổi: mọi thư mục đều tìm thấy, không có thay đổi
        let cmp = try ScanComparison.load(info.filePath, root: root)
        #expect(cmp.info == info)
        #expect(cmp.root === root)
        let all = allNodes(root)
        #expect(all.count == 5)
        var seen = Set<Int>()
        for n in all {
            let i = cmp.index(of: n)
            #expect(i >= 0)
            seen.insert(i)
            #expect(cmp.size(at: max(i, 0)) == n.size)
            #expect(cmp.files(at: max(i, 0)) == n.fileCount)
            #expect(cmp.sizeChange(n) == 0)
        }
        #expect(seen.count == all.count)
    }

    @Test func compareAfterChanges() async throws {
        let store = try TempSnapshots()
        defer { store.restore() }
        let t = try TempTree()
        try t.file("keep/a.bin", bytes: 50_000)
        try t.file("grow/b.bin", bytes: 20_000)
        let gone = try t.file("gone/c.bin", bytes: 40_000)
        let goneSize = TempTree.allocated(gone)
        let old = await scan(t.root)
        let info = try ScanSnapshot.save(old, scannedAt: Date(), errors: 0, appVersion: "1.0")

        let more = try t.file("grow/more.bin", bytes: 200_000)
        let added = try t.file("fresh/sub/n.bin", bytes: 30_000)
        try FileManager.default.removeItem(atPath: t.root + "/gone")
        let root = await scan(t.root)
        let cmp = try ScanComparison.load(info.filePath, root: root)

        let keep = try #require(child(root, "keep"))
        #expect(cmp.index(of: keep) >= 0)
        #expect(cmp.sizeChange(keep) == 0)

        let grow = try #require(child(root, "grow"))
        let gi = cmp.index(of: grow)
        #expect(gi >= 0)
        #expect(cmp.sizeChange(grow) == TempTree.allocated(more))
        #expect(cmp.sizeChange(grow) > 0)
        #expect(cmp.files(at: gi) == 1)
        #expect(cmp.index(of: grow) == gi) // lần hai lấy từ kết quả đã nhớ

        let fresh = try #require(child(root, "fresh"))
        let sub = try #require(child(fresh, "sub"))
        #expect(cmp.index(of: fresh) == -1)
        #expect(cmp.index(of: sub) == -1)
        #expect(cmp.sizeChange(fresh) == fresh.size)
        #expect(cmp.sizeChange(sub) == TempTree.allocated(added))

        #expect(cmp.index(of: root) == 0)
        #expect(cmp.size(at: 0) == info.totalSize)
        #expect(cmp.files(at: 0) == 3)
        #expect(cmp.sizeChange(root) == root.size - info.totalSize)
        #expect(cmp.sizeChange(root) == TempTree.allocated(more) + TempTree.allocated(added) - goneSize)

        // Thư mục của cây khác (lần quét cũ) không thuộc gốc đang so
        let oldKeep = try #require(child(old, "keep"))
        #expect(cmp.index(of: oldKeep) == -1)
    }

    @Test func manySiblingsAndConcurrentLookups() async throws {
        let store = try TempSnapshots()
        defer { store.restore() }
        let t = try TempTree()
        for k in 0..<300 { try t.dir("many/d\(k)") }
        let f = try t.file("many/d7/f.bin", bytes: 8_000)
        let root = await scan(t.root)
        let info = try ScanSnapshot.save(root, scannedAt: Date(), errors: 0, appVersion: "1.0")
        #expect(info.nodeCount == 302)

        let many = try #require(child(root, "many"))
        let kids = many.children
        let cmp = try ScanComparison.load(info.filePath, root: root)
        let indexes = kids.map { cmp.index(of: $0) }
        #expect(indexes.allSatisfy { $0 > 1 })
        #expect(Set(indexes).count == kids.count)
        let d7 = try #require(child(many, "d7"))
        #expect(cmp.size(at: cmp.index(of: d7)) == TempTree.allocated(f))

        // Dò từ nhiều luồng cùng lúc trên một bản so sánh mới
        let fresh = try ScanComparison.load(info.filePath, root: root)
        let results = OSAllocatedUnfairLock(initialState: [Int](repeating: -2, count: kids.count))
        DispatchQueue.concurrentPerform(iterations: kids.count) { i in
            let v = fresh.index(of: kids[i])
            results.withLock { $0[i] = v }
        }
        #expect(results.withLock { $0 } == indexes)
    }

    @Test func pruneKeepsNewest() async throws {
        let store = try TempSnapshots()
        defer { store.restore() }
        let t = try TempTree()
        try t.file("a/x.bin", bytes: 1_000)
        let root = await scan(t.root)

        let dir = ScanSnapshot.folder(for: t.root)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let staleTmp = dir + "/20200101-000000-000.dsnap.tmp"
        let recentTmp = dir + "/20200101-000000-001.dsnap.tmp"
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: staleTmp))
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: recentTmp))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: staleTmp)

        let start = Date(timeIntervalSince1970: 1_750_000_000)
        var saved: [SnapshotInfo] = []
        for i in 0..<5 {
            saved.append(try ScanSnapshot.save(root, scannedAt: start.addingTimeInterval(Double(i) * 90),
                                               errors: 0, appVersion: "1", keep: 3))
        }
        #expect(ScanSnapshot.list(t.root) == Array(saved.suffix(3).reversed()))
        #expect(!FileOps.exists(staleTmp))
        #expect(FileOps.exists(recentTmp))

        // Mặc định giữ keepPerRoot lần
        for i in 5..<17 {
            saved.append(try ScanSnapshot.save(root, scannedAt: start.addingTimeInterval(Double(i) * 90),
                                               errors: 0, appVersion: "1"))
        }
        let listed = ScanSnapshot.list(t.root)
        #expect(listed.count == ScanSnapshot.keepPerRoot)
        #expect(listed == Array(saved.suffix(ScanSnapshot.keepPerRoot).reversed()))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".dsnap") }
        #expect(files.count == ScanSnapshot.keepPerRoot)
    }

    @Test func usageAndDeleteAll() async throws {
        let store = try TempSnapshots()
        defer { store.restore() }
        // Thư mục lưu chưa có
        try FileManager.default.removeItem(atPath: store.folder)
        #expect(ScanSnapshot.usage().count == 0)
        #expect(ScanSnapshot.usage().bytes == 0)
        #expect(ScanSnapshot.deleteAll() == 0)

        let a = try TempTree()
        try a.file("x/1.bin", bytes: 2_000)
        let b = try TempTree()
        try b.file("y/2.bin", bytes: 3_000)
        let rootA = await scan(a.root)
        let rootB = await scan(b.root)
        let start = Date()
        let saved = [
            try ScanSnapshot.save(rootA, scannedAt: start, errors: 0, appVersion: "1"),
            try ScanSnapshot.save(rootA, scannedAt: start.addingTimeInterval(1), errors: 0, appVersion: "1"),
            try ScanSnapshot.save(rootB, scannedAt: start, errors: 0, appVersion: "1"),
        ]
        #expect(ScanSnapshot.folder(for: a.root) != ScanSnapshot.folder(for: b.root))
        let usage = ScanSnapshot.usage()
        let bytes = try saved.map { Int64(try Data(contentsOf: URL(fileURLWithPath: $0.filePath)).count) }.reduce(0, +)
        #expect(usage.count == 3)
        #expect(usage.bytes == bytes)
        #expect(bytes > 0)

        #expect(ScanSnapshot.deleteAll() == 3)
        #expect(ScanSnapshot.usage().count == 0)
        #expect(ScanSnapshot.list(a.root).isEmpty)
        #expect(ScanSnapshot.list(b.root).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.folder).isEmpty)
    }

    @Test func corruptFilesAreRejected() async throws {
        let store = try TempSnapshots()
        defer { store.restore() }
        let t = try TempTree()
        try t.file("a/b/x.bin", bytes: 5_000)
        try t.dir("c")
        let root = await scan(t.root)
        let info = try ScanSnapshot.save(root, scannedAt: Date(), errors: 0, appVersion: "1.0")
        let good = try Data(contentsOf: URL(fileURLWithPath: info.filePath))
        #expect(good.prefix(4) == Data("DSNP".utf8))
        let headerLength = try ScanSnapshot.parseHeader(good, file: info.filePath).length
        #expect(good.count > headerLength)
        let dir = ScanSnapshot.folder(for: t.root)

        func write(_ name: String, _ data: Data) throws -> String {
            let path = dir + "/" + name
            try data.write(to: URL(fileURLWithPath: path))
            return path
        }
        var noise = Data(count: 600)
        noise.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, 600) }

        // Phần đầu hỏng: readInfo trả nil, load ném lỗi
        var v2 = good
        v2[4] = 2
        let badHeaders = [
            try write("garbage.dsnap", noise),
            try write("empty.dsnap", Data()),
            try write("short.dsnap", good.prefix(20)),
            try write("headeronly.dsnap", good.prefix(headerLength)),
            try write("version2.dsnap", v2),
            try write("hugecount.dsnap", patched(good, at: headerLength - 8, Int32.max)),
            try write("zerocount.dsnap", patched(good, at: headerLength - 8, 0)),
        ]
        for path in badHeaders {
            #expect(ScanSnapshot.readInfo(path) == nil, "\(path)")
            #expect(throws: (any Error).self, "\(path)") { try ScanComparison.load(path, root: root) }
        }

        // Phần đầu còn tốt nhưng phần thân hỏng: chỉ phát hiện khi nạp
        let badBodies = [
            try write("cut.dsnap", good.prefix(headerLength + (good.count - headerLength) / 2)),
            try write("noisebody.dsnap", good.prefix(headerLength) + noise),
            try write("countplus.dsnap", patched(good, at: headerLength - 8, Int32(info.nodeCount + 1))),
            try write("countminus.dsnap", patched(good, at: headerLength - 8, Int32(info.nodeCount - 1))),
            try write("countlarge.dsnap", patched(good, at: headerLength - 8, 150_000_000)),
        ]
        for path in badBodies {
            #expect(throws: (any Error).self, "\(path)") { try ScanComparison.load(path, root: root) }
        }
        #expect(throws: (any Error).self) { try ScanComparison.load(dir + "/missing.dsnap", root: root) }

        // Danh sách bỏ qua file có phần đầu hỏng; file tốt vẫn nạp được
        let listed = ScanSnapshot.list(t.root).map(\.filePath)
        #expect(listed.contains(info.filePath))
        for path in badHeaders { #expect(!listed.contains(path)) }
        let cmp = try ScanComparison.load(info.filePath, root: root)
        #expect(cmp.sizeChange(root) == 0)
    }

    @Test func rootsAndFolderNames() throws {
        let store = try TempSnapshots()
        defer { store.restore() }
        let t = try TempTree()
        try t.dir("x")

        #expect(ScanSnapshot.normalize(t.root + "/") == t.root)
        #expect(ScanSnapshot.sameRoot("/", "/"))
        #expect(ScanSnapshot.sameRoot(t.root, t.root + "/"))
        #expect(ScanSnapshot.sameRoot(t.root, t.root + "/x/.."))
        #expect(!ScanSnapshot.sameRoot(t.root, "/"))
        #expect(!ScanSnapshot.sameRoot(t.root, t.root + "/x"))

        // FNV-1a 64 bit: giá trị chuẩn
        #expect(ScanSnapshot.nameHash("".utf8) == 0xcbf2_9ce4_8422_2325)
        #expect(ScanSnapshot.nameHash("a".utf8) == 0xaf63_dc4c_8601_ec8c)
        #expect(ScanSnapshot.nameHash("foobar".utf8) == 0x8594_4171_f739_67e8)

        let rootFolder = ScanSnapshot.folder(for: "/")
        #expect((rootFolder as NSString).deletingLastPathComponent == store.folder)
        #expect((rootFolder as NSString).lastPathComponent == "root-" + hex("/"))

        try t.dir("My Folder (2)")
        let normal = ScanSnapshot.folder(for: t.root + "/My Folder (2)")
        #expect((normal as NSString).deletingLastPathComponent == store.folder)
        #expect((normal as NSString).lastPathComponent == "My_Folder__2_-" + hex(t.root + "/My Folder (2)"))
        #expect(ScanSnapshot.folder(for: t.root + "/My Folder (2)/") == normal)
        #expect(ScanSnapshot.folder(for: t.root + "/x") != ScanSnapshot.folder(for: t.root))

        let long = String(repeating: "x", count: 40)
        try t.dir(long)
        #expect((ScanSnapshot.folder(for: t.root + "/" + long) as NSString).lastPathComponent
            == String(repeating: "x", count: 32) + "-" + hex(t.root + "/" + long))

        try t.dir("Tài liệu")
        #expect((ScanSnapshot.folder(for: t.root + "/Tài liệu") as NSString).lastPathComponent
            == "T_i_li_u-" + hex(t.root + "/Tài liệu"))
    }
}
