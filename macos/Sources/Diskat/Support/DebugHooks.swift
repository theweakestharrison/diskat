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
        defer {
            try? FileManager.default.removeItem(atPath: base)
            FileHandle.standardError.write("\(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")\n".data(using: .utf8)!)
            exit(failures == 0 ? 0 : 1)
        }

        await wait(1.0)
        await model.startScanAsync(base)
        guard let root = model.root else { check(false, "scan started"); return }
        check(root.fileCount == 6 && root.dirCount == 4, "scan counts (6 files, 4 folders)")
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
        check(root.size == before - dropSize && root.fileCount == 4 && root.dirCount == 2, "totals updated after folder delete")
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
        check(keep.size == keepBefore - fileRow.size && keep.ownFiles == 1, "folder totals after file delete")
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
        model.rightTab = .map

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
