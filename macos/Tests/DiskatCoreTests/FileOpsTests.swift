import Foundation
import Testing
@testable import DiskatCore

@Suite struct FormatTests {
    @Test func sizes() {
        #expect(FileOps.formatSize(0) == "0 B")
        #expect(FileOps.formatSize(999) == "999 B")
        #expect(FileOps.formatSize(1000) == "1.00 KB")
        #expect(FileOps.formatSize(12_345) == "12.3 KB")
        #expect(FileOps.formatSize(245_000_000_000) == "245 GB")
        #expect(FileOps.formatSize(1_500_000_000_000) == "1.50 TB")
    }

    @Test func counts() {
        #expect(FileOps.formatCount(0) == "0")
        #expect(FileOps.formatCount(999) == "999")
        #expect(FileOps.formatCount(1510) == "1,510")
        #expect(FileOps.formatCount(Int64(2_000_000)) == "2,000,000")
    }

    @Test func placeholders() {
        #expect(Loc.format("{0}  ·  {1} files  ·  {3:0.0}s", ["1 GB", "12", "x", 1.234]) == "1 GB  ·  12 files  ·  1.2s")
        #expect(Loc.format("Done in {0:0.0}s ({1} files/sec).", [0.04, "9"]) == "Done in 0.0s (9 files/sec).")
        #expect(Loc.format("{1} before {0}", ["a", "b"]) == "b before a")
        #expect(Loc.format("{missing} {9}", ["a"]) == "{missing} {9}")
    }

    @Test func paths() {
        #expect(FileOps.isPath("/a/b", inside: "/a"))
        #expect(FileOps.isPath("/a", inside: "/a"))
        #expect(!FileOps.isPath("/ab", inside: "/a"))
        #expect(FileOps.isPath("/x", inside: "/"))
        #expect(FileOps.join("/", "x") == "/x")
        #expect(FileOps.join("/a", "x") == "/a/x")
    }
}

@Suite struct ProtectionTests {
    let home = FileOps.resolvedPath(NSHomeDirectory())

    @Test func blocksVolumesAndSystem() {
        #expect(FileOps.protectionReason("/") != nil)
        #expect(FileOps.protectionReason("/System") != nil)
        #expect(FileOps.protectionReason("/System/Library/Fonts") != nil)
        #expect(FileOps.protectionReason("/usr/bin/true") != nil)
        #expect(FileOps.protectionReason("/private/etc/hosts") != nil)
        #expect(FileOps.protectionReason("/System/Volumes/Data") != nil)
        #expect(FileOps.protectionReason("relative/path") != nil)
    }

    @Test func blocksCriticalFoldersAndTheirParents() {
        for p in ["/Applications", "/Library", "/Users", "/usr", "/usr/local", "/private", "/private/var",
                  "/tmp", "/var", "/Volumes", home, home + "/Library", home + "/Library/Caches",
                  home + "/Documents", home + "/Desktop", home + "/Library/Mobile Documents"] {
            #expect(FileOps.protectionReason(p) != nil, "\(p) should be protected")
        }
        #expect(FileOps.protectionReason("/Users/someone") != nil)
    }

    @Test func allowsUserContent() {
        for p in [home + "/Library/Caches/com.example.app", home + "/Downloads/big.iso", home + "/Projects/node_modules",
                  "/Applications/Some App.app", "/Library/Caches/foo", "/usr/local/Cellar/thing",
                  "/private/tmp/scratch", "/tmp/scratch", "/System/Volumes/Data/Users/x/Downloads/file.zip"] {
            #expect(FileOps.protectionReason(p) == nil, "\(p) should be deletable")
        }
    }

    @Test func resolvesSymlinkedParents() throws {
        let t = try TempTree()
        let link = t.root + "/sys"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/System")
        // Thứ nằm "trong" symlink thực chất là /System/Library
        #expect(FileOps.protectionReason(link + "/Library") != nil)
        // Bản thân symlink thì xóa được (chỉ xóa liên kết)
        #expect(FileOps.protectionReason(link) == nil)
    }
}

@Suite struct TreemapTests {
    @Test func squarifyFillsTheRectangleWithoutOverlap() {
        let sizes: [Int64] = [500, 300, 120, 80, 40, 30, 20, 5, 3, 2]
        let rect = CGRect(x: 10, y: 20, width: 400, height: 250)
        var placed = [CGRect?](repeating: nil, count: sizes.count)
        TreemapLayout.squarify(sizes, in: rect) { placed[$0] = $1 }

        let rects = placed.compactMap { $0 }
        #expect(rects.count == sizes.count)
        let area = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        #expect(abs(area - Double(rect.width * rect.height)) < 1)
        for (i, a) in rects.enumerated() {
            #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(a))
            for b in rects[(i + 1)...] {
                let overlap = a.intersection(b)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
        // Tỉ lệ diện tích đúng với dung lượng
        let first = Double(rects[0].width * rects[0].height) / Double(rect.width * rect.height)
        #expect(abs(first - 500.0 / 1100.0) < 0.001)
    }
}

@Suite struct LocalizationTests {
    private func tokens(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\{[^}]*\}"#)
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .map { String(s[Range($0.range, in: s)!]) }.sorted()
    }

    @Test func everyLanguageHasEveryKeyAndPlaceholder() {
        let en = Strings.en
        for lang in Loc.languages {
            guard let table = Loc.tables[lang.code] else {
                Issue.record("missing table \(lang.code)")
                continue
            }
            #expect(Set(table.keys) == Set(en.keys), "\(lang.code): keys differ")
            for (key, value) in table {
                guard let source = en[key] else { continue }
                #expect(tokens(value) == tokens(source), "\(lang.code).\(key): placeholders differ")
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(lang.code).\(key): empty")
                #expect(!value.contains("—") && !value.contains("–"), "\(lang.code).\(key): long dash")
            }
        }
    }
}
