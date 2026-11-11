import Foundation
import XCTest
@testable import DiskatCore

final class ScanStatsTests: XCTestCase {
    private func key(_ name: String) -> String? {
        name.withCString { WorkerStats.extensionKey($0)?.string }
    }

    func testExtensions() {
        XCTAssertTrue(key("movie.MP4") == ".mp4")
        XCTAssertTrue(key("archive.tar.gz") == ".gz")
        XCTAssertTrue(key("README") == nil)
        XCTAssertTrue(key(".bashrc") == nil)
        XCTAssertTrue(key("file.") == nil)
        XCTAssertTrue(key("copy.2023 final") == nil)          // khoảng trắng: không phải phần mở rộng
        XCTAssertTrue(key("data.verylongextension") == nil)   // dài hơn 12 ký tự
        XCTAssertTrue(key("photo.jpeg") == ".jpeg")
    }

    func testTypesAndAgesFromAScan() async throws {
        let t = try TempTree()
        let a = try t.file("a.bin", bytes: 50_000)
        try t.file("sub/b.BIN", bytes: 20_000)
        let c = try t.file("c.txt", bytes: 9_000)
        let old = try t.file("old/d.log", bytes: 7_000)
        // Một file sửa lần cuối 3 năm trước
        let threeYears = Date().addingTimeInterval(-3 * 365 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: threeYears], ofItemAtPath: old)

        let scanner = DiskScanner(path: t.root)
        await scanner.run()

        let types = scanner.fileTypes()
        XCTAssertTrue(types.map(\.ext) == [".bin", ".txt", ".log"])
        XCTAssertTrue(types[0].count == 2)
        XCTAssertTrue(types[0].size == TempTree.allocated(a) + TempTree.allocated(t.root + "/sub/b.BIN"))
        XCTAssertTrue(types[1].size == TempTree.allocated(c))

        let ages = scanner.ageBuckets()
        XCTAssertTrue(ages.count == 6)
        XCTAssertTrue(ages.map(\.maxDays) == [30, 182, 365, 730, 1825, nil])
        XCTAssertTrue(ages[0].count == 3)
        XCTAssertTrue(ages[4].count == 1) // 2 đến 5 năm
        XCTAssertTrue(ages.reduce(0) { $0 + $1.size } == scanner.root.size)
    }
}

final class FileFinderTests: XCTestCase {
    func testPatterns() {
        XCTAssertTrue(FileFinder.parsePatterns("  ") == nil)
        XCTAssertTrue(FileFinder.parsePatterns("*.log; *.tmp") == ["*.log", "*.tmp"])
        XCTAssertTrue(FileFinder.parsePatterns("*.log *.tmp") == ["*.log", "*.tmp"])
        XCTAssertTrue(FileFinder.parsePatterns("invoice") == ["*invoice*"])
        XCTAssertTrue(FileFinder.parsePatterns("my invoice, report") == ["*my invoice*", "*report*"])
    }

    func testFindsByNameSizeAndAge() throws {
        let t = try TempTree()
        try t.file("logs/app.log", bytes: 30_000)
        try t.file("logs/APP2.LOG", bytes: 5_000)
        try t.file("big/video.mov", bytes: 400_000)
        let old = try t.file("big/old.mov", bytes: 200_000)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-400 * 86_400)], ofItemAtPath: old)
        try FileManager.default.createSymbolicLink(atPath: t.root + "/loop", withDestinationPath: t.root)

        let counter = FileFinder.Counter()
        let logs = try FileFinder.find(root: t.root, patterns: ["*.log"], minSize: 0, olderThan: nil, max: 10,
                                       counter: counter, isCancelled: { false })
        XCTAssertTrue(logs.total == 2) // không phân biệt hoa thường, không đi theo symlink
        XCTAssertTrue(counter.found == 2)

        let large = try FileFinder.find(root: t.root, patterns: nil, minSize: 100_000, olderThan: nil, max: 10,
                                        counter: counter, isCancelled: { false })
        XCTAssertTrue(large.files.map { ($0.path as NSString).lastPathComponent } == ["video.mov", "old.mov"])

        let yearAgo = Date().timeIntervalSince1970 - 365 * 86_400
        let aged = try FileFinder.find(root: t.root, patterns: nil, minSize: 0, olderThan: yearAgo, max: 10,
                                       counter: counter, isCancelled: { false })
        XCTAssertTrue(aged.files.map(\.path) == [old])

        let capped = try FileFinder.find(root: t.root, patterns: nil, minSize: 0, olderThan: nil, max: 1,
                                         counter: counter, isCancelled: { false })
        XCTAssertTrue(capped.files.count == 1 && capped.total == 4)

        XCTAssertThrowsError(try FileFinder.find(root: t.root, patterns: nil, minSize: 0, olderThan: nil, max: 10, counter: counter,
                                isCancelled: { true })) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
}

final class LaunchOptionsTests: XCTestCase {
    func testParsesArguments() {
        let o = LaunchOptions.parse(["/data", "--pdf", "/tmp/r.pdf", "--csv", "/tmp/f.csv", "--files-csv", "/tmp/g.csv",
                                     "--lang", "VI", "--compare", "--quit"])
        XCTAssertTrue(o.scanPath == "/data")
        XCTAssertTrue(o.pdfPath == "/tmp/r.pdf" && o.foldersCsvPath == "/tmp/f.csv" && o.filesCsvPath == "/tmp/g.csv")
        XCTAssertTrue(o.lang == "vi" && o.compare && o.quit && o.hasExports)
    }

    func testIgnoresAppKitArguments() {
        let o = LaunchOptions.parse(["-NSDocumentRevisionsDebugMode", "YES", "~/x", "--pdf", "rel.pdf"])
        XCTAssertTrue(o.scanPath == "~/x")
        XCTAssertTrue(o.pdfPath == FileManager.default.currentDirectoryPath + "/rel.pdf")
        XCTAssertTrue(!LaunchOptions.parse([]).hasExports)
    }
}

final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("1.1.0", than: "1.0.0"))
        XCTAssertTrue(Updater.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(Updater.isNewer("2.0", than: "1.9.9"))
        XCTAssertTrue(!Updater.isNewer("1.1.0", than: "1.1.0"))
        XCTAssertTrue(!Updater.isNewer("1.0.9", than: "1.1"))
    }
}
