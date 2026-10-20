import Foundation
import Testing
@testable import DiskatCore

/// Cây thư mục tạm cho mỗi test, tự xóa khi xong.
final class TempTree {
    let root: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("diskat-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = FileOps.resolvedPath(base.path)
    }

    deinit {
        FileOps.unlockForTests(root)
        try? FileManager.default.removeItem(atPath: root)
    }

    @discardableResult
    func file(_ rel: String, bytes: Int) throws -> String {
        let path = root + "/" + rel
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        // Dữ liệu ngẫu nhiên để APFS không nén / bỏ qua các khối toàn số 0
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, bytes) }
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    func dir(_ rel: String) throws {
        try FileManager.default.createDirectory(atPath: root + "/" + rel, withIntermediateDirectories: true)
    }

    /// Dung lượng thực trên đĩa, cùng cách tính với bộ quét.
    static func allocated(_ path: String) -> Int64 {
        var st = stat()
        lstat(path, &st)
        return Int64(st.st_blocks) * 512
    }
}

extension FileOps {
    static func unlockForTests(_ path: String) {
        _ = try? deletePermanently(path)
    }
}

@Suite struct ScannerTests {
    @Test func countsFilesFoldersAndSizes() async throws {
        let t = try TempTree()
        let a = try t.file("a.bin", bytes: 10_000)
        let b = try t.file("sub/b.bin", bytes: 250_000)
        let c = try t.file("sub/deep/c.bin", bytes: 3_000)
        try t.dir("empty")

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        let root = scanner.root

        #expect(root.isScanned)
        #expect(root.fileCount == 3)
        #expect(root.dirCount == 3) // sub, sub/deep, empty
        let expected = [a, b, c].map(TempTree.allocated).reduce(0, +)
        #expect(root.size == expected)
        #expect(root.isFullyScanned())
        #expect(scanner.errors == 0)

        let sub = try #require(root.children.first { $0.name == "sub" })
        #expect(sub.fullPath == t.root + "/sub")
        #expect(sub.ownFiles == 1)
        #expect(sub.size == TempTree.allocated(b) + TempTree.allocated(c))

        let top = scanner.topFiles()
        #expect(top.map(\.path) == [b, a, c])
    }

    @Test func symlinksAreNotFollowed() async throws {
        let t = try TempTree()
        try t.file("real/big.bin", bytes: 500_000)
        try FileManager.default.createSymbolicLink(atPath: t.root + "/link", withDestinationPath: t.root + "/real")
        try FileManager.default.createSymbolicLink(atPath: t.root + "/loop", withDestinationPath: t.root)

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        #expect(scanner.root.dirCount == 1)
        #expect(scanner.root.size < 600_000)
    }

    @Test func hardLinksAreCountedOnce() async throws {
        let t = try TempTree()
        let original = try t.file("one/data.bin", bytes: 400_000)
        try t.dir("two")
        try FileManager.default.linkItem(atPath: original, toPath: t.root + "/two/data.bin")

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        #expect(scanner.root.fileCount == 2)
        #expect(scanner.root.size == TempTree.allocated(original))
    }

    @Test func unreadableFolderIsReported() async throws {
        let t = try TempTree()
        try t.file("locked/secret.bin", bytes: 1000)
        chmod(t.root + "/locked", 0)
        defer { chmod(t.root + "/locked", 0o755) }

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        let locked = try #require(scanner.root.children.first)
        #expect(locked.isAccessDenied)
        #expect(scanner.errors == 1)
        #expect(!scanner.root.isFullyScanned())
    }

    @Test func detachAndRemoveFileUpdateTotals() async throws {
        let t = try TempTree()
        try t.file("keep/a.bin", bytes: 100_000)
        try t.file("drop/b.bin", bytes: 200_000)
        try t.file("drop/x/c.bin", bytes: 50_000)
        let f = try t.file("loose.bin", bytes: 30_000)

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        let root = scanner.root
        let before = root.size
        let drop = try #require(root.children.first { $0.name == "drop" })
        let dropSize = drop.size

        drop.detach()
        #expect(root.size == before - dropSize)
        #expect(root.fileCount == 2)
        #expect(root.dirCount == 1)
        #expect(!drop.isAttached(to: root))

        root.removeFile(size: TempTree.allocated(f))
        #expect(root.fileCount == 1)
        #expect(root.ownFiles == 0)
    }

    @Test func rescanAdoptsNewContents() async throws {
        let t = try TempTree()
        try t.file("sub/a.bin", bytes: 100_000)
        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        let sub = try #require(scanner.root.children.first)

        let extra = try t.file("sub/new/b.bin", bytes: 300_000)
        let fresh = DiskScanner(path: sub.fullPath)
        await fresh.run()
        sub.adopt(fresh.root)

        #expect(sub.fileCount == 2)
        #expect(scanner.root.fileCount == 2)
        #expect(scanner.root.dirCount == 2)
        #expect(scanner.root.size == sub.size)
        let added = try #require(sub.children.first)
        #expect(added.parent === sub)
        #expect(added.fullPath == (extra as NSString).deletingLastPathComponent)
    }

    @Test func listFilesMatchesScanner() throws {
        let t = try TempTree()
        try t.file("one.bin", bytes: 5000)
        try t.file("two.bin", bytes: 9000)
        try t.dir("folder")
        let files = FileOps.listFiles(t.root).sorted { $0.name < $1.name }
        #expect(files.map(\.name) == ["one.bin", "two.bin"])
        #expect(files[0].size == TempTree.allocated(t.root + "/one.bin"))
    }

    @Test func deletePermanentlyHandlesReadOnlyAndLockedItems() throws {
        let t = try TempTree()
        let locked = try t.file("ro/inner/locked.bin", bytes: 1000)
        lchflags(locked, UInt32(UF_IMMUTABLE))
        chmod(t.root + "/ro/inner", 0o555)
        chmod(t.root + "/ro", 0o555)
        try FileOps.deletePermanently(t.root + "/ro")
        #expect(!FileOps.exists(t.root + "/ro"))
    }

    @Test func cancelStopsEarly() async throws {
        let t = try TempTree()
        for i in 0..<50 { try t.dir("d\(i)/e/f") }
        let scanner = DiskScanner(path: t.root)
        scanner.cancel()
        await scanner.run()
        #expect(scanner.isCancelled)
    }
}
