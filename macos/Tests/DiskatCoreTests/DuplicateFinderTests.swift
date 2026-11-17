import Foundation
import XCTest
@testable import DiskatCore

/// Dữ liệu ngẫu nhiên (TempTree.file mỗi lần ghi một nội dung khác, nên tự ghi nội dung giống nhau ở đây).
private func randomData(_ count: Int) -> Data {
    var data = Data(count: count)
    data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, count) }
    return data
}

/// Ghi đúng nội dung `data`; `modified` (giây kể từ 1970) đặt lại thời gian sửa.
@discardableResult
private func writeFile(_ t: TempTree, _ rel: String, _ data: Data, modified: Double? = nil) throws -> String {
    let path = t.root + "/" + rel
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                            withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: path))
    if let modified {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified)],
                                              ofItemAtPath: path)
    }
    return path
}

private func findDups(_ root: String, minSize: Int64 = 1, skipSystem: Bool = false,
                      progress: DuplicateFinder.Progress = .init()) throws -> DupResult {
    try DuplicateFinder.find(root: root, minSize: minSize, skipSystem: skipSystem, progress: progress,
                             cancel: DuplicateFinder.CancelFlag())
}

final class DuplicateFinderTests: XCTestCase {
    func testIdenticalFilesInDifferentFoldersFormOneGroup() throws {
        let t = try TempTree()
        let data = randomData(100_000)
        let a = try writeFile(t, "a/one.bin", data, modified: 1_600_000_000)
        let b = try writeFile(t, "b/two.bin", data, modified: 1_700_000_000)
        let c = try writeFile(t, "c/deep/three.bin", data, modified: 1_650_000_000)
        try writeFile(t, "other.bin", randomData(100_000)) // cùng dung lượng, khác nội dung
        try t.file("small.bin", bytes: 500)

        let progress = DuplicateFinder.Progress()
        let r = try findDups(t.root, progress: progress)
        XCTAssertTrue(r.files == 5)
        XCTAssertTrue(r.unreadable == 0)
        XCTAssertTrue(r.cloudSkipped == 0)
        XCTAssertTrue(r.groups.count == 1)
        let g = try XCTUnwrap(r.groups.first)
        XCTAssertTrue(g.size == 100_000)
        XCTAssertTrue(g.wasted == 200_000)
        XCTAssertTrue(g.files.map(\.path) == [b, c, a]) // mới sửa nhất trước
        XCTAssertTrue(g.files.allSatisfy { !$0.isHardLinked && !$0.isClone && $0.otherNames.isEmpty && $0.linkCount == 1 })
        XCTAssertTrue(g.files[0].modified == 1_700_000_000)
        XCTAssertTrue(progress.stage == 2)
        XCTAssertTrue(progress.found == 5)
    }

    func testGroupsAreSortedByWasted() throws {
        let t = try TempTree()
        let small = randomData(50_000), big = randomData(40_000)
        try writeFile(t, "s1.bin", small)
        try writeFile(t, "s2.bin", small)
        for i in 0..<3 { try writeFile(t, "b\(i).bin", big) }

        let r = try findDups(t.root)
        XCTAssertTrue(r.groups.map(\.wasted) == [80_000, 50_000])
        XCTAssertTrue(r.groups.map(\.files.count) == [3, 2])
    }

    func testSameSizeDifferentContentIsNotGrouped() throws {
        let t = try TempTree()
        try t.file("x.bin", bytes: 70_000)
        try t.file("sub/y.bin", bytes: 70_000)
        let r = try findDups(t.root)
        XCTAssertTrue(r.files == 2)
        XCTAssertTrue(r.groups.isEmpty)
    }

    func testSameHeadDifferentTailIsNotGrouped() throws {
        let t = try TempTree()
        let size = 300_000
        let d1 = randomData(size)
        var d2 = d1
        d2[size - 1] ^= 0xFF // chỉ khác byte cuối
        var d3 = d1
        d3[100_000] ^= 0x01 // khác ngay sau 64 KB đầu
        let a = try writeFile(t, "a.bin", d1)
        try writeFile(t, "b.bin", d2)
        try writeFile(t, "c.bin", d3)
        let d = try writeFile(t, "d.bin", d1)

        let progress = DuplicateFinder.Progress()
        let r = try findDups(t.root, progress: progress)
        XCTAssertTrue(r.groups.count == 1)
        XCTAssertTrue(Set(r.groups[0].files.map(\.path)) == [a, d])
        XCTAssertTrue(r.groups[0].wasted == Int64(size))
        // Cả bốn file cùng 64 KB đầu nên đều được băm phần còn lại
        XCTAssertTrue(progress.total == 4 * Int64(size - DuplicateFinder.headSize))
        XCTAssertTrue(progress.done == progress.total)
    }

    func testMinSizeFiltersSmallFiles() throws {
        let t = try TempTree()
        let small = randomData(1_000), big = randomData(10_000)
        try writeFile(t, "s1.bin", small)
        try writeFile(t, "s2.bin", small)
        try writeFile(t, "b1.bin", big)
        try writeFile(t, "b2.bin", big)
        try writeFile(t, "e1.bin", Data())
        try writeFile(t, "e2.bin", Data())

        let r = try findDups(t.root, minSize: 5_000)
        XCTAssertTrue(r.files == 2)
        XCTAssertTrue(r.groups.map(\.size) == [10_000])

        // minSize 0 vẫn bỏ file rỗng (giống nhau nhưng không tốn chỗ)
        let all = try findDups(t.root, minSize: 0)
        XCTAssertTrue(all.files == 4)
        XCTAssertTrue(all.groups.map(\.size) == [10_000, 1_000])
    }

    func testHardLinksAreMerged() throws {
        let t = try TempTree()
        let data = randomData(80_000)
        let original = try writeFile(t, "one/f.bin", data)
        try t.dir("two")
        let link = t.root + "/two/f.bin"
        try FileManager.default.linkItem(atPath: original, toPath: link)
        let copy = try writeFile(t, "three/g.bin", data)

        let r = try findDups(t.root)
        XCTAssertTrue(r.files == 3)
        XCTAssertTrue(r.groups.count == 1)
        let g = try XCTUnwrap(r.groups.first)
        XCTAssertTrue(g.files.count == 2)
        let linked = try XCTUnwrap(g.files.first { $0.path == original })
        XCTAssertTrue(linked.otherNames == [link])
        XCTAssertTrue(linked.linkCount == 2)
        XCTAssertTrue(linked.isHardLinked)
        let plain = try XCTUnwrap(g.files.first { $0.path == copy })
        XCTAssertTrue(!plain.isHardLinked)
        XCTAssertTrue(plain.otherNames.isEmpty)
        XCTAssertTrue(g.wasted == 80_000)
    }

    func testGroupWhereEveryFileIsHardLinkedIsDropped() throws {
        let t = try TempTree()
        let data = randomData(60_000)
        // Hai file khác nhau (cùng nội dung), mỗi file có hai tên
        let p = try writeFile(t, "p/1.bin", data)
        try FileManager.default.linkItem(atPath: p, toPath: t.root + "/p/1b.bin")
        let q = try writeFile(t, "q/2.bin", data)
        try FileManager.default.linkItem(atPath: q, toPath: t.root + "/q/2b.bin")
        // Một file với hai tên: không phải bản sao
        let x = try t.file("x.bin", bytes: 30_000)
        try FileManager.default.linkItem(atPath: x, toPath: t.root + "/y.bin")

        let r = try findDups(t.root)
        XCTAssertTrue(r.files == 6)
        XCTAssertTrue(r.groups.isEmpty)
    }

    func testSymlinksAreNotFollowed() throws {
        let t = try TempTree()
        let real = try t.file("real/data.bin", bytes: 50_000)
        let fm = FileManager.default
        try fm.createSymbolicLink(atPath: t.root + "/link", withDestinationPath: t.root + "/real")
        try fm.createSymbolicLink(atPath: t.root + "/alias.bin", withDestinationPath: real)
        try fm.createSymbolicLink(atPath: t.root + "/loop", withDestinationPath: t.root)

        let r = try findDups(t.root)
        XCTAssertTrue(r.files == 1)
        XCTAssertTrue(r.groups.isEmpty)
    }

    func testSkipSystemSkipsPackages() throws {
        let t = try TempTree()
        let data = randomData(40_000)
        let inApp = try writeFile(t, "Foo.app/Contents/Resources/x.bin", data)
        try writeFile(t, "Bar.photoslibrary/originals/x.bin", data)
        let doc = try writeFile(t, "docs/x.bin", data)
        try writeFile(t, ".Trashes/x.bin", data) // luôn bỏ qua
        try writeFile(t, "sub/.Trash/x.bin", data)

        let skipped = try findDups(t.root, skipSystem: true)
        XCTAssertTrue(skipped.files == 1)
        XCTAssertTrue(skipped.groups.isEmpty)

        let included = try findDups(t.root, skipSystem: false)
        XCTAssertTrue(included.files == 3)
        XCTAssertTrue(included.groups.count == 1)
        let paths = Set(included.groups.first?.files.map(\.path) ?? [])
        XCTAssertTrue(paths.contains(inApp))
        XCTAssertTrue(paths.contains(doc))
        XCTAssertTrue(!paths.contains { $0.contains("/.Trash") })
    }

    func testPackageDetectionUsesTypeConformance() {
        XCTAssertTrue(DuplicateFinder.isPackage("Safari.app"))
        XCTAssertTrue(DuplicateFinder.isPackage("Foo.FRAMEWORK"))
        XCTAssertTrue(DuplicateFinder.isPackage("Photos Library.photoslibrary"))
        XCTAssertTrue(!DuplicateFinder.isPackage("notes.txt"))
        XCTAssertTrue(!DuplicateFinder.isPackage("Folder"))
        XCTAssertTrue(!DuplicateFinder.isPackage(".app"))
        XCTAssertTrue(!DuplicateFinder.isPackage("v1.2"))
    }

    func testClonesAreDetected() throws {
        let t = try TempTree()
        let size = 300_000
        let data = randomData(size)
        let a = try writeFile(t, "a.bin", data)
        let b = t.root + "/b.bin"
        XCTAssertTrue(clonefile(a, b, 0) == 0, "clonefile cần ổ APFS")
        let c = try writeFile(t, "c.bin", data) // bản sao thật, không dùng chung khối

        let r = try findDups(t.root)
        XCTAssertTrue(r.groups.count == 1)
        let g = try XCTUnwrap(r.groups.first)
        XCTAssertTrue(g.files.count == 3)
        let byPath = Dictionary(uniqueKeysWithValues: g.files.map { ($0.path, $0) })
        XCTAssertTrue(byPath[a]?.isClone == true)
        XCTAssertTrue(byPath[b]?.isClone == true)
        XCTAssertTrue(byPath[c]?.isClone == false)
        // a và b là một vùng dữ liệu: chỉ một bản thừa
        XCTAssertTrue(g.wasted == Int64(size))
    }

    func testGroupOfOnlyClonesWastesNothing() throws {
        let t = try TempTree()
        let a = try t.file("a.bin", bytes: 200_000)
        XCTAssertTrue(clonefile(a, t.root + "/b.bin", 0) == 0, "clonefile cần ổ APFS")

        let r = try findDups(t.root)
        XCTAssertTrue(r.groups.count == 1)
        let g = try XCTUnwrap(r.groups.first)
        XCTAssertTrue(g.files.allSatisfy { $0.isClone })
        XCTAssertTrue(g.wasted == 0)
    }

    func testClonesOutsideTheScanAreCounted() throws {
        let t = try TempTree()
        let size = 150_000
        let data = randomData(size)
        // Clone nằm trong .Trash (không quét): xóa bản trong nhóm cũng không lấy lại được chỗ
        try t.dir(".Trash")
        let a = try writeFile(t, "a.bin", data)
        XCTAssertTrue(clonefile(a, t.root + "/.Trash/a.bin", 0) == 0, "clonefile cần ổ APFS")
        let c = try writeFile(t, "c.bin", data)

        var r = try findDups(t.root)
        var g = try XCTUnwrap(r.groups.first)
        XCTAssertTrue(g.files.first { $0.path == a }?.isClone == true)
        XCTAssertTrue(g.files.first { $0.path == c }?.isClone == false)
        XCTAssertTrue(g.wasted == Int64(size))

        XCTAssertTrue(clonefile(c, t.root + "/.Trash/c.bin", 0) == 0)
        r = try findDups(t.root)
        g = try XCTUnwrap(r.groups.first)
        XCTAssertTrue(g.files.allSatisfy { $0.isClone })
        XCTAssertTrue(g.wasted == 0)
    }

    func testUnreadableFilesAreCounted() throws {
        let t = try TempTree()
        let data = randomData(20_000)
        try writeFile(t, "a.bin", data)
        let b = try writeFile(t, "b.bin", data)
        chmod(b, 0)
        defer { chmod(b, 0o644) }

        let r = try findDups(t.root)
        XCTAssertTrue(r.files == 2)
        XCTAssertTrue(r.unreadable == 1)
        XCTAssertTrue(r.groups.isEmpty)
    }

    func testMissingRootThrows() {
        XCTAssertThrowsError(try findDups("/nonexistent-diskat-\(UUID().uuidString)")) { error in
            XCTAssertTrue(error is POSIXError)
        }
    }

    func testCancellationThrows() throws {
        let t = try TempTree()
        let data = randomData(100_000)
        try writeFile(t, "a.bin", data)
        try writeFile(t, "b.bin", data)
        let cancel = DuplicateFinder.CancelFlag()
        cancel.cancel()
        XCTAssertTrue(cancel.isCancelled)
        XCTAssertThrowsError(try DuplicateFinder.find(root: t.root, minSize: 1, skipSystem: false,
                                     progress: DuplicateFinder.Progress(), cancel: cancel)) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
}
