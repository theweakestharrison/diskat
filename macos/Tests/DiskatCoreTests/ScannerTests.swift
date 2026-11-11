import Foundation
import XCTest
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

final class ScannerTests: XCTestCase {
    func testCountsFilesFoldersAndSizes() async throws {
        let t = try TempTree()
        let a = try t.file("a.bin", bytes: 10_000)
        let b = try t.file("sub/b.bin", bytes: 250_000)
        let c = try t.file("sub/deep/c.bin", bytes: 3_000)
        try t.dir("empty")

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        let root = scanner.root

        XCTAssertTrue(root.isScanned)
        XCTAssertTrue(root.fileCount == 3)
        XCTAssertTrue(root.dirCount == 3) // sub, sub/deep, empty
        let expected = [a, b, c].map(TempTree.allocated).reduce(0, +)
        XCTAssertTrue(root.size == expected)
        XCTAssertTrue(root.isFullyScanned())
        XCTAssertTrue(scanner.errors == 0)

        let sub = try XCTUnwrap(root.children.first { $0.name == "sub" })
        XCTAssertTrue(sub.fullPath == t.root + "/sub")
        XCTAssertTrue(sub.ownFiles == 1)
        XCTAssertTrue(sub.size == TempTree.allocated(b) + TempTree.allocated(c))

        let top = scanner.topFiles()
        XCTAssertTrue(top.map(\.path) == [b, a, c])
    }

    func testSymlinksAreNotFollowed() async throws {
        let t = try TempTree()
        try t.file("real/big.bin", bytes: 500_000)
        try FileManager.default.createSymbolicLink(atPath: t.root + "/link", withDestinationPath: t.root + "/real")
        try FileManager.default.createSymbolicLink(atPath: t.root + "/loop", withDestinationPath: t.root)

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        XCTAssertTrue(scanner.root.dirCount == 1)
        XCTAssertTrue(scanner.root.size < 600_000)
    }

    func testHardLinksAreCountedOnce() async throws {
        let t = try TempTree()
        let original = try t.file("one/data.bin", bytes: 400_000)
        try t.dir("two")
        try FileManager.default.linkItem(atPath: original, toPath: t.root + "/two/data.bin")

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        XCTAssertTrue(scanner.root.fileCount == 2)
        XCTAssertTrue(scanner.root.size == TempTree.allocated(original))
    }

    func testUnreadableFolderIsReported() async throws {
        let t = try TempTree()
        try t.file("locked/secret.bin", bytes: 1000)
        chmod(t.root + "/locked", 0)
        defer { chmod(t.root + "/locked", 0o755) }

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        let locked = try XCTUnwrap(scanner.root.children.first)
        XCTAssertTrue(locked.isAccessDenied)
        XCTAssertTrue(scanner.errors == 1)
        XCTAssertTrue(!scanner.root.isFullyScanned())
    }

    func testDetachAndRemoveFileUpdateTotals() async throws {
        let t = try TempTree()
        try t.file("keep/a.bin", bytes: 100_000)
        try t.file("drop/b.bin", bytes: 200_000)
        try t.file("drop/x/c.bin", bytes: 50_000)
        let f = try t.file("loose.bin", bytes: 30_000)

        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        let root = scanner.root
        let before = root.size
        let drop = try XCTUnwrap(root.children.first { $0.name == "drop" })
        let dropSize = drop.size

        drop.detach()
        XCTAssertTrue(root.size == before - dropSize)
        XCTAssertTrue(root.fileCount == 2)
        XCTAssertTrue(root.dirCount == 1)
        XCTAssertTrue(!drop.isAttached(to: root))

        root.removeFile(size: TempTree.allocated(f))
        XCTAssertTrue(root.fileCount == 1)
        XCTAssertTrue(root.ownFiles == 0)
    }

    func testRescanAdoptsNewContents() async throws {
        let t = try TempTree()
        try t.file("sub/a.bin", bytes: 100_000)
        let scanner = DiskScanner(path: t.root)
        await scanner.run()
        let sub = try XCTUnwrap(scanner.root.children.first)

        let extra = try t.file("sub/new/b.bin", bytes: 300_000)
        let fresh = DiskScanner(path: sub.fullPath)
        await fresh.run()
        sub.adopt(fresh.root)

        XCTAssertTrue(sub.fileCount == 2)
        XCTAssertTrue(scanner.root.fileCount == 2)
        XCTAssertTrue(scanner.root.dirCount == 2)
        XCTAssertTrue(scanner.root.size == sub.size)
        let added = try XCTUnwrap(sub.children.first)
        XCTAssertTrue(added.parent === sub)
        XCTAssertTrue(added.fullPath == (extra as NSString).deletingLastPathComponent)
    }

    func testListFilesMatchesScanner() throws {
        let t = try TempTree()
        try t.file("one.bin", bytes: 5000)
        try t.file("two.bin", bytes: 9000)
        try t.dir("folder")
        let files = FileOps.listFiles(t.root).sorted { $0.name < $1.name }
        XCTAssertTrue(files.map(\.name) == ["one.bin", "two.bin"])
        XCTAssertTrue(files[0].size == TempTree.allocated(t.root + "/one.bin"))
    }

    func testDeletePermanentlyHandlesReadOnlyAndLockedItems() throws {
        let t = try TempTree()
        let locked = try t.file("ro/inner/locked.bin", bytes: 1000)
        lchflags(locked, UInt32(UF_IMMUTABLE))
        chmod(t.root + "/ro/inner", 0o555)
        chmod(t.root + "/ro", 0o555)
        try FileOps.deletePermanently(t.root + "/ro")
        XCTAssertTrue(!FileOps.exists(t.root + "/ro"))
    }

    func testCancelStopsEarly() async throws {
        let t = try TempTree()
        for i in 0..<50 { try t.dir("d\(i)/e/f") }
        let scanner = DiskScanner(path: t.root)
        scanner.cancel()
        await scanner.run()
        XCTAssertTrue(scanner.isCancelled)
    }
}
