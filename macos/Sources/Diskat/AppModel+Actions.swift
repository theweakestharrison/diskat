import AppKit
import DiskatCore

/// Các thao tác trên mục đang chọn: mở, sao chép, xóa, quét lại (tương ứng MainWindow.Actions.cs).
extension AppModel {
    // ================= Cây =================

    func revealSelected() {
        if let d = selectedDir { Finder.showFolder(d.fullPath) }
        else if let f = selectedFile { Finder.reveal(f.fullPath) }
    }

    func openSelected() {
        if let p = selectedPath { Finder.open(p) }
    }

    func copySelectedPath() {
        if let p = selectedPath { Finder.copy(p) }
    }

    func showSelectedOnMap() {
        let target = selectedDir ?? selectedFile?.owner
        guard let target, !target.isMount else { return }
        setMapRoot(target)
        rightTab = .map
    }

    var rescanTarget: DirNode? {
        guard let target = selectedDir ?? selectedFile?.owner, !target.isMount else { return nil }
        return target
    }

    func rescanSelected() {
        if let target = rescanTarget { Task { await rescanNode(target) } }
    }

    // ================= Theo vùng đang dùng (cây / file lớn nhất) =================

    private var largestFilesActive: Bool { activePane == .largest && rightTab == .largest && !topSelection.isEmpty }

    var canDeleteActive: Bool {
        if pathFieldFocused { return false }
        return largestFilesActive ? !isBusy && !isScanning : canDeleteSelection
    }

    func deleteActive(permanent: Bool) {
        Task {
            if largestFilesActive { await deleteTopFiles(permanent: permanent) }
            else { await deleteSelected(permanent: permanent) }
        }
    }

    func copyActive() {
        if largestFilesActive { copyTopFiles() } else { copySelectedPath() }
    }

    func revealActive() {
        if largestFilesActive { revealTopFile() } else { revealSelected() }
    }

    // ================= Xóa =================

    private func setBusy(_ busy: Bool) {
        isBusy = busy
    }

    /// Trả về true nếu được phép bắt đầu xóa; nếu không thì báo cho người dùng.
    private func canStartDelete() async -> Bool {
        if isBusy { return false }
        if !isScanning { return true }
        await Dialogs.alert(Loc.t("MsgWaitScan"))
        return false
    }

    private func confirmDelete(what: String, path: String, size: Int64, detail: String, permanent: Bool, warning: String? = nil) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var finished = false
            confirm = ConfirmRequest(permanent: permanent, what: what, path: path, size: FileOps.formatSize(size),
                                     detail: detail, warning: warning) { [weak self] ok in
                guard !finished else { return }
                finished = true
                self?.confirm = nil
                cont.resume(returning: ok)
            }
        }
    }

    /// Xóa ở luồng nền (hiện lớp phủ). Trả về false nếu lỗi (đã báo cho người dùng).
    private func runDelete(_ path: String, permanent: Bool) async -> Bool {
        busyText = Loc.t(permanent ? "DeletingPerm" : "Trashing")
        defer { busyText = nil }
        do {
            try await Task.detached(priority: .userInitiated) {
                if permanent { try FileOps.deletePermanently(path) }
                else { try FileOps.moveToTrash(path) }
            }.value
            return true
        } catch {
            busyText = nil
            await Dialogs.alert(Loc.t("MsgDeleteErrorTitle"), detail: Loc.f("MsgDeleteFailed", path, error.localizedDescription), style: .critical)
            return false
        }
    }

    func deleteSelected(permanent: Bool) async {
        guard hasSelection, let item = selection, await canStartDelete() else { return }
        if let d = item as? DirNode, d === root {
            await Dialogs.alert(Loc.t("MsgRootDelete"))
            return
        }
        guard let path = selectedPath else { return }
        if let reason = FileOps.protectionReason(path) {
            await Dialogs.alert(Loc.t("MsgNotAllowed"), detail: "\(reason)\n\n\(path)", style: .critical)
            return
        }

        let dir = item as? DirNode
        let file = item as? FileRow
        let size = dir?.size ?? file?.size ?? 0
        let detail = dir.map { Loc.f("DetailDir", FileOps.formatCount($0.fileCount), FileOps.formatCount($0.dirCount)) } ?? ""
        // Thư mục chưa quét xong (đã bấm Dừng / bị chặn quyền): số liệu trong hộp thoại có thể thiếu
        let warning = dir.map { $0.isFullyScanned() ? nil : Loc.t("ConfirmIncomplete") } ?? nil

        setBusy(true)
        defer { setBusy(false) }
        guard await confirmDelete(what: Loc.t(dir != nil ? "WhatFolder" : "WhatFile"), path: path, size: size,
                                  detail: detail, permanent: permanent, warning: warning) else { return }

        let index = tree?.selectedRowIndex ?? 0
        _ = await runDelete(path, permanent: permanent)

        if let dir {
            if !FileOps.exists(path) {
                dir.detach()
                fileRowCacheRemove(dir)
                removeTopFiles(under: path)
                afterTreeChanged(selectingRow: index)
                let freed = FileOps.formatSize(size)
                setStatus { Loc.f("Freed", freed, path) }
            } else {
                // Xóa không trọn vẹn (bị hủy hoặc lỗi): quét lại để số liệu chính xác
                await rescanCore(dir)
            }
        } else if let file, !FileOps.exists(path) {
            applyFileRemoved(owner: file.owner, row: file, size: size)
            removeTopFiles(under: path)
            afterTreeChanged(selectingRow: index)
            let freed = FileOps.formatSize(size)
            setStatus { Loc.f("Freed", freed, path) }
        }
    }

    private func applyFileRemoved(owner: DirNode, row: FileRow?, size: Int64) {
        owner.removeFile(size: size)
        fileRowCacheRemove(owner, keeping: row)
    }

    /// Cập nhật lại cây/bản đồ sau khi xóa và chọn dòng kế bên.
    private func afterTreeChanged(selectingRow oldIndex: Int) {
        // Thư mục đang xem trên bản đồ (hoặc một thư mục cha của nó) đã bị xóa
        if let m = mapRoot, let root, !m.isAttached(to: root) { setMapRoot(root) }
        rebuildTree()
        tree?.selectRow(oldIndex)
        tree?.focus()
        setMapRoot(mapRoot ?? root)
        bumpValues()
    }

    // ================= Quét lại một thư mục =================

    func rescanNode(_ node: DirNode) async {
        guard !isBusy, !isScanning, let root, !node.isMount else { return }
        if node === root {
            await startScanAsync(root.fullPath)
            return
        }
        setBusy(true)
        defer { setBusy(false) }
        await rescanCore(node)
    }

    private func rescanCore(_ node: DirNode) async {
        guard let root, node.isAttached(to: root) else { return }
        let path = node.fullPath
        if !FileOps.isDirectory(path) {
            node.detach()
            afterTreeChanged(selectingRow: Int.max)
            return
        }

        setStatus { Loc.f("Rescanning", path) }
        isRescanning = true
        let sc = DiskScanner(path: path)
        await sc.run()
        isRescanning = false

        node.adopt(sc.root)
        fileRowCacheRemoveAll()
        pruneMissingTopFiles(under: path)
        afterTreeChanged(selectingRow: tree?.selectedRowIndex ?? 0)
        let newSize = FileOps.formatSize(node.size)
        setStatus { Loc.f("Rescanned", path, newSize) }
    }

    // ================= File lớn nhất =================

    func loadTopFiles() {
        topFiles = (scanner?.topFiles() ?? []).map { TopFile(path: $0.path, size: $0.size, modified: $0.modified) }
        topSelection = []
    }

    private func removeTopFiles(under path: String) {
        topFiles.removeAll { FileOps.isPath($0.path, inside: path) }
        topSelection = topSelection.filter { !FileOps.isPath($0, inside: path) }
    }

    /// Sau khi quét lại một thư mục: bỏ các file trong đó đã không còn tồn tại.
    private func pruneMissingTopFiles(under path: String) {
        topFiles.removeAll { FileOps.isPath($0.path, inside: path) && !FileOps.exists($0.path) }
        topSelection = topSelection.filter { id in topFiles.contains { $0.id == id } }
    }

    var selectedTopFiles: [TopFile] { topFiles.filter { topSelection.contains($0.id) } }

    func revealTopFile() {
        if let f = selectedTopFiles.first { Finder.reveal(f.path) }
    }

    func openTopFile() {
        if let f = selectedTopFiles.first { Finder.open(f.path) }
    }

    func copyTopFiles() {
        let files = selectedTopFiles
        if !files.isEmpty { Finder.copy(files.map(\.path).joined(separator: "\n")) }
    }

    func deleteTopFiles(permanent: Bool) async {
        var files = selectedTopFiles
        guard !files.isEmpty, root != nil, await canStartDelete() else { return }

        // File đã bị xóa ở nơi khác: chỉ gỡ khỏi danh sách, không trừ dung lượng lần nữa
        for gone in files where !FileOps.exists(gone.path) { removeTopFiles(under: gone.path) }
        files.removeAll { !FileOps.exists($0.path) }
        guard !files.isEmpty else { return }

        for f in files {
            if let reason = FileOps.protectionReason(f.path) {
                await Dialogs.alert(Loc.t("MsgNotAllowed"), detail: "\(reason)\n\n\(f.path)", style: .critical)
                return
            }
        }

        let total = files.reduce(Int64(0)) { $0 + $1.size }
        let label = files.count == 1 ? files[0].path : Loc.f("SelectedFiles", files.count)

        setBusy(true)
        defer { setBusy(false) }
        guard await confirmDelete(what: files.count == 1 ? Loc.t("WhatFile") : Loc.f("WhatFiles", files.count),
                                  path: label, size: total, detail: "", permanent: permanent) else { return }

        var freed: Int64 = 0
        for f in files {
            if !(await runDelete(f.path, permanent: permanent)) { break }
            if FileOps.exists(f.path) { break }

            freed += f.size
            if let owner = findNode(f.folder) { applyFileRemoved(owner: owner, row: nil, size: f.size) }
            removeTopFiles(under: f.path)
        }

        afterTreeChanged(selectingRow: tree?.selectedRowIndex ?? 0)
        if freed > 0 {
            let text = FileOps.formatSize(freed)
            setStatus { Loc.f("FreedShort", text) }
        }
    }

    private func findNode(_ dirPath: String) -> DirNode? {
        guard let root else { return nil }
        let base = root.fullPath
        guard FileOps.isPath(dirPath, inside: base) else { return nil }
        if dirPath == base { return root }
        let rel = dirPath.dropFirst(base.hasSuffix("/") ? base.count : base.count + 1)
        var cur = root
        for part in rel.split(separator: "/") {
            guard let next = cur.children.first(where: { $0.name == part }) else { return nil }
            cur = next
        }
        return cur
    }
}
