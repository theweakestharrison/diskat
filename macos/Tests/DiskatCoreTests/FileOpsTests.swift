import Foundation
import XCTest
@testable import DiskatCore

final class FormatTests: XCTestCase {
    func testSizes() {
        XCTAssertTrue(FileOps.formatSize(0) == "0 B")
        XCTAssertTrue(FileOps.formatSize(999) == "999 B")
        XCTAssertTrue(FileOps.formatSize(1000) == "1.00 KB")
        XCTAssertTrue(FileOps.formatSize(12_345) == "12.3 KB")
        XCTAssertTrue(FileOps.formatSize(245_000_000_000) == "245 GB")
        XCTAssertTrue(FileOps.formatSize(1_500_000_000_000) == "1.50 TB")
    }

    func testCounts() {
        XCTAssertTrue(FileOps.formatCount(0) == "0")
        XCTAssertTrue(FileOps.formatCount(999) == "999")
        XCTAssertTrue(FileOps.formatCount(1510) == "1,510")
        XCTAssertTrue(FileOps.formatCount(Int64(2_000_000)) == "2,000,000")
    }

    func testPlaceholders() {
        XCTAssertTrue(Loc.format("{0}  ·  {1} files  ·  {3:0.0}s", ["1 GB", "12", "x", 1.234]) == "1 GB  ·  12 files  ·  1.2s")
        XCTAssertTrue(Loc.format("Done in {0:0.0}s ({1} files/sec).", [0.04, "9"]) == "Done in 0.0s (9 files/sec).")
        XCTAssertTrue(Loc.format("{1} before {0}", ["a", "b"]) == "b before a")
        XCTAssertTrue(Loc.format("{missing} {9}", ["a"]) == "{missing} {9}")
    }

    func testPaths() {
        XCTAssertTrue(FileOps.isPath("/a/b", inside: "/a"))
        XCTAssertTrue(FileOps.isPath("/a", inside: "/a"))
        XCTAssertTrue(!FileOps.isPath("/ab", inside: "/a"))
        XCTAssertTrue(FileOps.isPath("/x", inside: "/"))
        XCTAssertTrue(FileOps.join("/", "x") == "/x")
        XCTAssertTrue(FileOps.join("/a", "x") == "/a/x")
    }
}

final class ProtectionTests: XCTestCase {
    let home = FileOps.resolvedPath(NSHomeDirectory())

    func testBlocksVolumesAndSystem() {
        XCTAssertTrue(FileOps.protectionReason("/") != nil)
        XCTAssertTrue(FileOps.protectionReason("/System") != nil)
        XCTAssertTrue(FileOps.protectionReason("/System/Library/Fonts") != nil)
        XCTAssertTrue(FileOps.protectionReason("/usr/bin/true") != nil)
        XCTAssertTrue(FileOps.protectionReason("/private/etc/hosts") != nil)
        XCTAssertTrue(FileOps.protectionReason("/System/Volumes/Data") != nil)
        XCTAssertTrue(FileOps.protectionReason("relative/path") != nil)
    }

    func testBlocksCriticalFoldersAndTheirParents() {
        for p in ["/Applications", "/Library", "/Users", "/usr", "/usr/local", "/private", "/private/var",
                  "/tmp", "/var", "/Volumes", home, home + "/Library", home + "/Library/Caches",
                  home + "/Documents", home + "/Desktop", home + "/Library/Mobile Documents"] {
            XCTAssertTrue(FileOps.protectionReason(p) != nil, "\(p) should be protected")
        }
        XCTAssertTrue(FileOps.protectionReason("/Users/someone") != nil)
    }

    func testAllowsUserContent() {
        for p in [home + "/Library/Caches/com.example.app", home + "/Downloads/big.iso", home + "/Projects/node_modules",
                  "/Applications/Some App.app", "/Library/Caches/foo", "/usr/local/Cellar/thing",
                  "/private/tmp/scratch", "/tmp/scratch", "/System/Volumes/Data/Users/x/Downloads/file.zip"] {
            XCTAssertTrue(FileOps.protectionReason(p) == nil, "\(p) should be deletable")
        }
    }

    func testResolvesSymlinkedParents() throws {
        let t = try TempTree()
        let link = t.root + "/sys"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/System")
        // Thứ nằm "trong" symlink thực chất là /System/Library
        XCTAssertTrue(FileOps.protectionReason(link + "/Library") != nil)
        // Bản thân symlink thì xóa được (chỉ xóa liên kết)
        XCTAssertTrue(FileOps.protectionReason(link) == nil)
    }
}

final class TreemapTests: XCTestCase {
    func testSquarifyFillsTheRectangleWithoutOverlap() {
        let sizes: [Int64] = [500, 300, 120, 80, 40, 30, 20, 5, 3, 2]
        let rect = CGRect(x: 10, y: 20, width: 400, height: 250)
        var placed = [CGRect?](repeating: nil, count: sizes.count)
        TreemapLayout.squarify(sizes, in: rect) { placed[$0] = $1 }

        let rects = placed.compactMap { $0 }
        XCTAssertTrue(rects.count == sizes.count)
        let area = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        XCTAssertTrue(abs(area - Double(rect.width * rect.height)) < 1)
        for (i, a) in rects.enumerated() {
            XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(a))
            for b in rects[(i + 1)...] {
                let overlap = a.intersection(b)
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
        // Tỉ lệ diện tích đúng với dung lượng
        let first = Double(rects[0].width * rects[0].height) / Double(rect.width * rect.height)
        XCTAssertTrue(abs(first - 500.0 / 1100.0) < 0.001)
    }
}

final class LocalizationTests: XCTestCase {
    private func tokens(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\{[^}]*\}"#)
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .map { String(s[Range($0.range, in: s)!]) }.sorted()
    }

    func testEveryLanguageHasEveryKeyAndPlaceholder() {
        let en = Strings.en
        for lang in Loc.languages {
            guard let table = Loc.tables[lang.code] else {
                XCTFail("missing table \(lang.code)")
                continue
            }
            XCTAssertTrue(Set(table.keys) == Set(en.keys), "\(lang.code): keys differ")
            for (key, value) in table {
                guard let source = en[key] else { continue }
                XCTAssertTrue(tokens(value) == tokens(source), "\(lang.code).\(key): placeholders differ")
                XCTAssertTrue(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(lang.code).\(key): empty")
                XCTAssertTrue(!value.contains("—") && !value.contains("–"), "\(lang.code).\(key): long dash")
            }
        }
    }
}
