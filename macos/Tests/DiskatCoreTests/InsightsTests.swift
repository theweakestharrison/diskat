import Foundation
import Testing
@testable import DiskatCore

@Suite struct ScanStatsTests {
    private func key(_ name: String) -> String? {
        name.withCString { WorkerStats.extensionKey($0)?.string }
    }

    @Test func extensions() {
        #expect(key("movie.MP4") == ".mp4")
        #expect(key("archive.tar.gz") == ".gz")
        #expect(key("README") == nil)
        #expect(key(".bashrc") == nil)
        #expect(key("file.") == nil)
        #expect(key("copy.2023 final") == nil)          // khoảng trắng: không phải phần mở rộng
        #expect(key("data.verylongextension") == nil)   // dài hơn 12 ký tự
        #expect(key("photo.jpeg") == ".jpeg")
    }

    @Test func typesAndAgesFromAScan() async throws {
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
        #expect(types.map(\.ext) == [".bin", ".txt", ".log"])
        #expect(types[0].count == 2)
        #expect(types[0].size == TempTree.allocated(a) + TempTree.allocated(t.root + "/sub/b.BIN"))
        #expect(types[1].size == TempTree.allocated(c))

        let ages = scanner.ageBuckets()
        #expect(ages.count == 6)
        #expect(ages.map(\.maxDays) == [30, 182, 365, 730, 1825, nil])
        #expect(ages[0].count == 3)
        #expect(ages[4].count == 1) // 2 đến 5 năm
        #expect(ages.reduce(0) { $0 + $1.size } == scanner.root.size)
    }
}

@Suite struct FileFinderTests {
    @Test func patterns() {
        #expect(FileFinder.parsePatterns("  ") == nil)
        #expect(FileFinder.parsePatterns("*.log; *.tmp") == ["*.log", "*.tmp"])
        #expect(FileFinder.parsePatterns("*.log *.tmp") == ["*.log", "*.tmp"])
        #expect(FileFinder.parsePatterns("invoice") == ["*invoice*"])
        #expect(FileFinder.parsePatterns("my invoice, report") == ["*my invoice*", "*report*"])
    }

    @Test func findsByNameSizeAndAge() throws {
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
        #expect(logs.total == 2) // không phân biệt hoa thường, không đi theo symlink
        #expect(counter.found == 2)

        let large = try FileFinder.find(root: t.root, patterns: nil, minSize: 100_000, olderThan: nil, max: 10,
                                        counter: counter, isCancelled: { false })
        #expect(large.files.map { ($0.path as NSString).lastPathComponent } == ["video.mov", "old.mov"])

        let yearAgo = Date().timeIntervalSince1970 - 365 * 86_400
        let aged = try FileFinder.find(root: t.root, patterns: nil, minSize: 0, olderThan: yearAgo, max: 10,
                                       counter: counter, isCancelled: { false })
        #expect(aged.files.map(\.path) == [old])

        let capped = try FileFinder.find(root: t.root, patterns: nil, minSize: 0, olderThan: nil, max: 1,
                                         counter: counter, isCancelled: { false })
        #expect(capped.files.count == 1 && capped.total == 4)

        #expect(throws: CancellationError.self) {
            try FileFinder.find(root: t.root, patterns: nil, minSize: 0, olderThan: nil, max: 10, counter: counter,
                                isCancelled: { true })
        }
    }
}

@Suite struct LaunchOptionsTests {
    @Test func parsesArguments() {
        let o = LaunchOptions.parse(["/data", "--pdf", "/tmp/r.pdf", "--csv", "/tmp/f.csv", "--files-csv", "/tmp/g.csv",
                                     "--lang", "VI", "--compare", "--quit"])
        #expect(o.scanPath == "/data")
        #expect(o.pdfPath == "/tmp/r.pdf" && o.foldersCsvPath == "/tmp/f.csv" && o.filesCsvPath == "/tmp/g.csv")
        #expect(o.lang == "vi" && o.compare && o.quit && o.hasExports)
    }

    @Test func ignoresAppKitArguments() {
        let o = LaunchOptions.parse(["-NSDocumentRevisionsDebugMode", "YES", "~/x", "--pdf", "rel.pdf"])
        #expect(o.scanPath == "~/x")
        #expect(o.pdfPath == FileManager.default.currentDirectoryPath + "/rel.pdf")
        #expect(!LaunchOptions.parse([]).hasExports)
    }
}

@Suite struct UpdaterTests {
    @Test func versionComparison() {
        #expect(Updater.isNewer("1.1.0", than: "1.0.0"))
        #expect(Updater.isNewer("1.10.0", than: "1.9.2"))
        #expect(Updater.isNewer("2.0", than: "1.9.9"))
        #expect(!Updater.isNewer("1.1.0", than: "1.1.0"))
        #expect(!Updater.isNewer("1.0.9", than: "1.1"))
    }
}
