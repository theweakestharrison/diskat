#if DEBUG
import AppKit
import DiskatCore

/// Chỉ có trong bản Debug: chụp ảnh các trạng thái giao diện để kiểm tra mà không cần thao tác tay.
///   DISKAT_SNAPSHOT_DIR=/tmp/shots swift run Diskat ~/Projects
/// Sau khi quét xong: chụp cửa sổ chính, mở rộng một thư mục, tab "File lớn nhất", giao diện tối,
/// hộp xác nhận xóa, tiếng Việt; rồi thoát.
///
///   DISKAT_SELFTEST=1 swift run Diskat
/// Tạo một cây thư mục tạm, chạy các luồng xóa vĩnh viễn / quét lại qua đúng các hàm mà nút bấm gọi
/// (tự bấm "Xóa" trong hộp xác nhận), kiểm tra cây và số liệu, in kết quả rồi thoát (mã 0 nếu đạt).
@MainActor
enum DebugHooks {
    static func install(_ model: AppModel) {
        if ProcessInfo.processInfo.environment["DISKAT_SELFTEST"] != nil {
            Task { await selfTest(model) }
            return
        }
        guard let dir = ProcessInfo.processInfo.environment["DISKAT_SNAPSHOT_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let scan = ProcessInfo.processInfo.environment["DISKAT_SNAPSHOT_SCAN"] {
            Task {
                await wait(1.0)
                model.startScan(scan)
            }
        }
        Task { await run(model, dir) }
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // ================= Tự kiểm tra =================

    private static var failures = 0

    private static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1 }
        FileHandle.standardError.write("\(ok ? "PASS" : "FAIL")  \(what)\n".data(using: .utf8)!)
    }

    private static func write(_ path: String, _ bytes: Int) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, bytes) }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// Chờ hộp xác nhận hiện ra rồi bấm đồng ý.
    private static func autoConfirm(_ model: AppModel) async {
        for _ in 0..<50 {
            if let c = model.confirm {
                await wait(0.3)
                c.resolve(true)
                return
            }
            await wait(0.1)
        }
        check(false, "confirm dialog appeared")
    }

    private static func selfTest(_ model: AppModel) async {
        let base = FileOps.resolvedPath(NSTemporaryDirectory()) + "/diskat-selftest-\(UUID().uuidString)"
        write(base + "/keep/a.bin", 300_000)
        write(base + "/keep/b.bin", 20_000)
        write(base + "/drop/c.bin", 500_000)
        write(base + "/drop/sub/d.bin", 100_000)
        write(base + "/grow/e.bin", 50_000)
        write(base + "/loose.bin", 700_000)
        write(base + "/keep/notes.txt", 4_000)
        // Lần quét đã lưu của bài kiểm tra không lẫn vào lịch sử thật
        let savedBase = ScanSnapshot.baseFolder
        ScanSnapshot.baseFolder = base + "-snapshots"
        defer {
            ScanSnapshot.baseFolder = savedBase
            try? FileManager.default.removeItem(atPath: base + "-snapshots")
            try? FileManager.default.removeItem(atPath: base)
            FileHandle.standardError.write("\(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")\n".data(using: .utf8)!)
            exit(failures == 0 ? 0 : 1)
        }

        await wait(1.0)
        await model.startScanAsync(base)
        guard let root = model.root else { check(false, "scan started"); return }
        check(root.fileCount == 7 && root.dirCount == 4, "scan counts (7 files, 4 folders)")
        check(model.fileTypes.first?.ext == ".bin" && model.fileTypes.first?.count == 6, "file types: .bin first with 6 files")
        check(model.fileTypes.contains { $0.ext == ".txt" && $0.count == 1 }, "file types: .txt")
        check(model.ageStats.count == 6 && model.ageStats[0].count == 7, "file ages: all files in the newest bucket")

        // Tìm file theo mẫu tên
        model.findText = "*.txt; loose"
        await model.runFind()
        check(Set(model.searchResults?.map(\.name) ?? []) == ["notes.txt", "loose.bin"], "find by name patterns")
        model.findText = ""
        model.findSizeIndex = 2 // 10 MB trở lên
        await model.runFind()
        check(model.searchResults?.isEmpty == true, "find by minimum size")
        model.findSizeIndex = 0
        model.clearSearch()
        check(model.searchResults == nil, "back to largest files")

        // Xuất báo cáo
        check(await model.exportPdf(to: base + "-report.pdf"), "PDF export")
        let pdf = CGPDFDocument(URL(fileURLWithPath: base + "-report.pdf") as CFURL)
        check((pdf?.numberOfPages ?? 0) >= 1, "PDF has pages")
        check(await model.exportFoldersCsv(to: base + "-folders.csv"), "folders CSV export")
        let csv = (try? Data(contentsOf: URL(fileURLWithPath: base + "-folders.csv"))) ?? Data()
        check(csv.starts(with: [0xEF, 0xBB, 0xBF]) && String(decoding: csv, as: UTF8.self).components(separatedBy: "\r\n").count == 7,
              "folders CSV: BOM, header and 5 folders")
        try? FileManager.default.removeItem(atPath: base + "-report.pdf")
        try? FileManager.default.removeItem(atPath: base + "-folders.csv")
        await model.waitForSnapshot()
        check(ScanSnapshot.list(base).count == 1, "scan saved for comparing later")
        check(model.topFiles.first?.path == base + "/loose.bin", "largest file first")

        // Thư mục gốc không xóa được
        model.tree?.selectRow(0)
        check(!model.canDeleteSelection, "root is not deletable")

        // Xóa vĩnh viễn một thư mục
        let drop = root.children.first { $0.name == "drop" }!
        let dropSize = drop.size
        let before = root.size
        check(model.tree?.reveal(drop) == true && model.selectedDir === drop, "select folder from code")
        check(model.mapRoot === drop, "map follows tree selection")
        async let confirmed: Void = autoConfirm(model)
        await model.deleteSelected(permanent: true)
        await confirmed
        check(!FileOps.exists(base + "/drop"), "folder deleted from disk")
        check(root.size == before - dropSize && root.fileCount == 5 && root.dirCount == 2, "totals updated after folder delete")
        check(!root.children.contains { $0 === drop }, "folder removed from tree")
        check(model.mapRoot.map { $0.isAttached(to: root) } ?? false, "map moved off deleted folder")
        check(!model.topFiles.contains { $0.path.hasPrefix(base + "/drop/") }, "largest files pruned")

        // Xóa vĩnh viễn một file trong cây
        let keep = root.children.first { $0.name == "keep" }!
        model.tree?.expand(keep)
        let fileRow = model.fileRows(of: keep).first { $0.name == "a.bin" }!
        check(model.tree?.reveal(fileRow) == true, "select file row")
        let keepBefore = keep.size
        async let confirmed2: Void = autoConfirm(model)
        await model.deleteSelected(permanent: true)
        await confirmed2
        check(!FileOps.exists(base + "/keep/a.bin"), "file deleted from disk")
        check(keep.size == keepBefore - fileRow.size && keep.ownFiles == 2, "folder totals after file delete")
        check(!model.fileRows(of: keep).contains { $0 === fileRow }, "file row removed")

        // Xóa từ tab "File lớn nhất"
        model.rightTab = .largest
        model.topSelection = [base + "/loose.bin"]
        model.activePane = .largest
        check(model.canDeleteActive, "largest files delete enabled")
        let rootBefore = root.size
        model.deleteActive(permanent: true)
        await autoConfirm(model)
        await wait(1.0)
        check(!FileOps.exists(base + "/loose.bin"), "top file deleted from disk")
        check(root.ownFiles == 0 && root.size < rootBefore, "root totals after top file delete")
        check(!model.topFiles.contains { $0.path == base + "/loose.bin" }, "top file removed from list")
        model.rightTab = .map

        // Chặn xóa thư mục hệ thống
        check(FileOps.protectionReason("/System/Library") != nil, "system folder protected")

        // Quét lại một thư mục
        let grow = root.children.first { $0.name == "grow" }!
        write(base + "/grow/new/f.bin", 400_000)
        let files = root.fileCount
        await model.rescanNode(grow)
        check(grow.fileCount == 2 && root.fileCount == files + 1 && grow.children.count == 1, "rescan picks up new files")

        // Sắp xếp theo tên
        model.setSort(.name, descending: false)
        let names = model.children(of: root).compactMap { ($0 as? DirNode)?.name }
        check(names == ["grow", "keep"], "sort by name")
        model.setSort(.size, descending: true)

        // So sánh với lần quét đầu tiên
        await model.startScanAsync(base)
        await model.waitForSnapshot()
        check(model.savedScans.count == 1, "earlier scan listed for comparing")
        if let first = model.savedScans.first {
            await model.startComparison(first)
            guard let root2 = model.root else { return }
            let grow2 = root2.children.first { $0.name == "grow" }!
            let new2 = grow2.children.first { $0.name == "new" }!
            check(model.isComparing && model.comparisonIsNew(new2), "new folder marked as new")
            check(model.comparisonChange(grow2) == new2.size, "grown folder change")
            check(model.comparisonChange(root2).map { $0 < 0 } == true, "root shrank after deletes")
            check(model.compareSummary?.isEmpty == false, "compare summary")
            model.setSort(.change, descending: true)
            check((model.children(of: root2).first as? DirNode)?.name == "grow", "sort by change")
            model.setSort(.size, descending: true)
            model.stopComparison()
            check(!model.isComparing && model.comparisonChange(grow2) == nil, "stop comparing")
        }

        // Trùng lặp: hai bản giống hệt (2 MB) và một bản cùng cỡ khác nội dung
        var same = Data(count: 2_000_000)
        same.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, 2_000_000) }
        try? FileManager.default.createDirectory(atPath: base + "/dups/one", withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: base + "/dups/two", withIntermediateDirectories: true)
        try? same.write(to: URL(fileURLWithPath: base + "/dups/one/x.dat"))
        try? same.write(to: URL(fileURLWithPath: base + "/dups/two/x.dat"))
        write(base + "/dups/other.dat", 2_000_000)
        // Bản trong "two" mới hơn: "Chọn tất cả trừ bản mới nhất" phải đánh dấu bản trong "one"
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: base + "/dups/one/x.dat")
        await model.startScanAsync(base)
        guard let root3 = model.root else { return }
        let dup = model.duplicates
        dup.minSizeIndex = 1
        await dup.run(root: root3)
        check(dup.groups?.count == 1 && dup.groups?.first?.files.count == 2, "duplicates: one group of two copies")
        check(dup.groups?.first?.wasted == 2_000_000, "duplicates: wasted space")
        if let g = dup.groups?.first {
            dup.setChecked(g.files[0], true)
            dup.setChecked(g.files[1], true)
            check(g.checkedCount == 1 && dup.notice != nil, "duplicates: last copy can't be selected")
            dup.clearChecks()
            dup.selectAllButNewest()
            check(g.files.filter(\.isChecked).map(\.path) == [base + "/dups/one/x.dat"], "duplicates: select all but newest")
            let before = root3.size
            async let confirmed: Void = autoConfirm(model)
            await model.deleteDuplicates(permanent: true)
            await confirmed
            check(!FileOps.exists(base + "/dups/one/x.dat") && FileOps.exists(base + "/dups/two/x.dat"), "duplicates: only the selected copy deleted")
            check(root3.size < before, "duplicates: tree totals updated")
            check(dup.groups?.isEmpty == true, "duplicates: group gone after delete")
        }
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && !$0.isSheet }
    }

    static func capture(_ name: String, _ dir: String) {
        guard let window else {
            FileHandle.standardError.write("snapshot \(name): no window among \(NSApp.windows.map { "\($0.className) visible=\($0.isVisible)" })\n".data(using: .utf8)!)
            return
        }
        let targets: [(NSWindow, String)] = [(window, name)] + (window.attachedSheet.map { [($0, name + "-sheet")] } ?? [])
        for (w, n) in targets {
            guard let view = w.contentView?.superview ?? w.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            do {
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + n + ".png"))
            } catch {
                FileHandle.standardError.write("snapshot \(n): \(error)\n".data(using: .utf8)!)
            }
        }
    }

    private static func run(_ model: AppModel, _ dir: String) async {
        // Lần quét đã lưu của lần chụp không lẫn vào lịch sử thật
        let snapshots = dir + "/snapshots"
        ScanSnapshot.baseFolder = snapshots

        // Chờ cửa sổ hiện và quét xong
        await wait(1.5)
        if model.root == nil { capture("0-empty", dir) }
        while model.root == nil || model.isScanning { await wait(0.3) }
        await wait(1.0)
        capture("1-main", dir)

        if let root = model.root, let first = model.children(of: root).first(where: { $0 is DirNode }) as? DirNode {
            model.tree?.expand(first)
            model.tree?.reveal(first)
            if let deeper = model.children(of: first).first(where: { $0 is DirNode }) as? DirNode {
                model.tree?.expand(deeper)
            }
        }
        await wait(0.8)
        capture("2-expanded", dir)

        model.rightTab = .largest
        await wait(0.8)
        capture("3-largest", dir)
        model.findText = "*.dylib"
        model.findSizeIndex = 1
        await model.runFind()
        await wait(0.6)
        capture("3b-find", dir)
        model.clearSearch()
        model.findText = ""
        model.findSizeIndex = 0
        model.rightTab = .types
        await wait(0.8)
        capture("3c-types", dir)
        model.rightTab = .ages
        await wait(0.8)
        capture("3d-ages", dir)
        if let root = model.root {
            model.rightTab = .duplicates
            model.duplicates.skipSystem = false
            await model.duplicates.run(root: root)
            model.duplicates.selectAllButNewest()
            await wait(0.8)
            capture("3e-duplicates", dir)
            model.duplicates.skipSystem = true
        }
        model.rightTab = .map

        // So sánh: quét lại cùng thư mục rồi so với lần trước
        if let path = model.root?.fullPath {
            await model.startScanAsync(path)
            await model.waitForSnapshot()
            if let first = model.savedScans.first { await model.startComparison(first) }
            await wait(1.0)
            capture("3f-compare", dir)
            model.stopComparison()
        }

        // Chụp giao diện còn lại (sáng nếu hệ thống đang tối và ngược lại)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSApp.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)
        await wait(1.0)
        capture(dark ? "4-light" : "4-dark", dir)
        NSApp.appearance = nil

        model.confirm = ConfirmRequest(permanent: true, what: Loc.t("WhatFolder"), path: model.selectedPath ?? "/tmp/x",
                                       size: "1.23 GB", detail: Loc.f("DetailDir", "1,234", "56"),
                                       warning: Loc.t("ConfirmIncomplete")) { _ in model.confirm = nil }
        await wait(1.0)
        capture("5-confirm", dir)
        model.confirm = nil
        await wait(0.5)

        let previous = Loc.lang
        model.setLanguage("vi")
        await wait(1.0)
        capture("6-vi", dir)
        model.setLanguage(previous)

        NSApp.terminate(nil)
    }
}
#endif
