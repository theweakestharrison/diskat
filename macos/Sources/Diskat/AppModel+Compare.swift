import AppKit
import DiskatCore

/// Lịch sử quét: lưu cây thư mục sau mỗi lần quét xong (ScanSnapshot, chỉ trên máy này) và so cây đang
/// hiển thị với một lần quét trước. Khi so sánh, cây có thêm cột "Thay đổi", nhãn "mới" cho thư mục mới,
/// và dòng tóm tắt phía trên (tương ứng MainWindow.Compare.cs của bản Windows).
extension AppModel {
    private func when(_ date: Date) -> String { FileOps.formatDate(date.timeIntervalSince1970) }

    private func signed(_ n: Int64) -> String { (n > 0 ? "+" : n < 0 ? "-" : "") + FileOps.formatCount(Int64(n.magnitude)) }

    /// Đang so sánh lần quét đang hiển thị
    var isComparing: Bool { comparison.map { $0.root === root } ?? false }

    // ================= Lưu =================

    /// Gọi khi quét xong: lưu lần quét này (nếu không bị dừng) rồi so tiếp với lần quét đã chọn.
    func scanFinishedCompare(cancelled: Bool) {
        guard !cancelled, let root, let sc = scanner else {
            refreshSavedScans()
            return
        }
        if saveScanHistory {
            let scannedAt = sc.startedAt, errors = sc.errors, version = Updater.currentVersion
            let previous = snapshotTask
            // Khoảng 0,1 giây cho 150.000 thư mục, ở luồng nền nên không làm chậm giao diện
            snapshotTask = Task.detached(priority: .utility) { [weak self] in
                await previous?.value
                // Ổ đầy, không có quyền ghi...: chỉ mất lần lưu này, kết quả quét không ảnh hưởng
                _ = try? ScanSnapshot.save(root, scannedAt: scannedAt, errors: errors, appVersion: version)
                await self?.refreshSavedScans()
            }
        } else {
            refreshSavedScans()
        }

        if let info = compareWith {
            if FileOps.exists(info.filePath) { Task { await startComparison(info, quiet: true) } }
            else { compareWith = nil }
        }
    }

    func waitForSnapshot() async {
        await snapshotTask?.value
    }

    /// Đọc lại danh sách lần quét đã lưu cho menu (bỏ lần đang hiển thị: so với chính nó thì không có gì để xem).
    func refreshSavedScans() {
        guard let root else {
            savedScans = []
            savedScanCount = ScanSnapshot.usage().count
            return
        }
        let current = scanner?.startedAt
        savedScans = ScanSnapshot.list(root.fullPath).filter { s in
            guard let current else { return true }
            return abs(s.scannedAt.timeIntervalSince(current)) >= 0.002
        }
        savedScanCount = ScanSnapshot.usage().count
    }

    // ================= So sánh =================

    func startComparison(_ info: SnapshotInfo, quiet: Bool = false) async {
        guard let root, !isScanning else { return }
        let path = info.filePath
        do {
            let cmp = try await Task.detached(priority: .userInitiated) { try ScanComparison.load(path, root: root) }.value
            // Trong lúc nạp, người dùng đã bắt đầu quét lại hoặc quét thư mục khác
            guard root === self.root, !isScanning else { return }
            comparison = cmp
            compareWith = info
            applyComparison()
        } catch {
            if quiet { compareWith = nil }
            else { await Dialogs.alert(Loc.f("CompareLoadFailed", error.localizedDescription), style: .warning) }
        }
    }

    func stopComparison() {
        comparison = nil
        compareWith = nil
        applyComparison()
    }

    /// Bắt đầu quét mới: tắt so sánh trong lúc quét. Quét lại đúng thư mục đang so thì so tiếp khi quét xong.
    func suspendComparison(newRoot: String) {
        if let info = compareWith, !ScanSnapshot.sameRoot(info.rootPath, newRoot) { compareWith = nil }
        if comparison != nil {
            comparison = nil
            tree?.applyComparison(false)
        }
        savedScans = []
    }

    /// --compare: so với lần quét đã lưu gần nhất trước lần này (cho báo cáo PDF từ dòng lệnh).
    func compareWithPrevious() async {
        guard let root, let sc = scanner else { return }
        let current = sc.startedAt
        if let previous = ScanSnapshot.list(root.fullPath).first(where: { $0.scannedAt < current.addingTimeInterval(-0.002) }) {
            await startComparison(previous, quiet: true)
        }
    }

    private func applyComparison() {
        tree?.applyComparison(isComparing)
        bumpValues()
    }

    // ================= Số liệu cho cây và báo cáo =================

    /// Dung lượng thay đổi so với lần quét cũ (thư mục mới: toàn bộ dung lượng); nil khi không so sánh.
    func comparisonChange(_ node: DirNode) -> Int64? {
        guard let c = comparison, c.root === root else { return nil }
        return c.sizeChange(node)
    }

    func comparisonIsNew(_ node: DirNode) -> Bool {
        guard let c = comparison, c.root === root else { return false }
        return c.index(of: node) < 0
    }

    func changeTip(_ node: DirNode) -> String? {
        guard let c = comparison, c.root === root else { return nil }
        let i = c.index(of: node)
        let at = when(c.info.scannedAt)
        return i < 0 ? Loc.f("ChangeTipNew", at)
            : Loc.f("ChangeTip", FileOps.formatSize(c.size(at: i)), FileOps.formatSize(node.size), at)
    }

    /// "Tăng 3.2 GB so với lần quét lúc ..." và số file thay đổi: cho thanh tóm tắt và báo cáo PDF.
    var compareSummary: String? {
        _ = valuesRevision
        guard let c = comparison, let root, c.root === root else { return nil }
        let delta = c.sizeChange(root)
        let files = root.fileCount - c.files(at: 0)
        let at = when(c.info.scannedAt)
        var text = delta > 0 ? Loc.f("CompareGrew", FileOps.formatSize(delta), at)
            : delta < 0 ? Loc.f("CompareShrank", FileOps.formatSize(-delta), at)
            : Loc.f("CompareSame", at)
        if files != 0 { text += "  ·  " + Loc.f("CompareFiles", signed(files)) }
        return text
    }

    // ================= Xóa các lần đã lưu =================

    func deleteSavedScans() async {
        // Đợi lần lưu đang chạy (nếu có) để không còn sót lại file vừa ghi
        await waitForSnapshot()
        let usage = ScanSnapshot.usage()
        guard usage.count > 0 else { return }
        let answer = await Dialogs.alert(Loc.f("CompareClearAsk", FileOps.formatCount(usage.count), FileOps.formatSize(usage.bytes)),
                                         style: .warning, buttons: [Loc.t("Delete"), Loc.t("Cancel")])
        guard answer == .alertFirstButtonReturn else { return }
        stopComparison()
        let deleted = await Task.detached { ScanSnapshot.deleteAll() }.value
        refreshSavedScans()
        setStatus { Loc.f("CompareCleared", FileOps.formatCount(deleted)) }
    }
}
