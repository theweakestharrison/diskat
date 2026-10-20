import AppKit
import os
import DiskatCore

/// Cờ hủy dùng chung giữa luồng giao diện và luồng nền.
final class CancelToken: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    func cancel() { state.withLockUnchecked { $0 = true } }
    var isCancelled: Bool { state.withLockUnchecked { $0 } }
}

/// Tab Loại file, Tuổi file và thanh tìm file (theo tên, dung lượng, tuổi) ở tab File lớn nhất
/// (tương ứng MainWindow.Insights.cs của bản Windows).
extension AppModel {
    nonisolated static let maxFindResults = 5000
    // Đơn vị thập phân giống Finder (1 MB = 1.000.000 byte)
    static let findSizes: [Int64] = [0, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000]
    static let findSizeLabels = ["", "1 MB", "10 MB", "100 MB", "1 GB"]
    static let findAgeDays = [0, 30, 182, 365, 730, 1825]

    func setActivePane(_ pane: ActivePane) {
        if activePane != pane { activePane = pane }
    }

    // ================= Loại file / tuổi file =================

    func resetInsights() {
        fileTypes = []
        ageStats = []
        statsStale = false
        cancelFind()
        searchResults = nil
        searchCapped = false
        findError = nil
    }

    /// Gọi khi quét xong: thống kê được gộp từ các luồng quét.
    func loadInsights() {
        guard let sc = scanner, !isScanning else { return }
        fileTypes = sc.fileTypes()
        ageStats = sc.ageBuckets()
    }

    var typesNote: String {
        guard let root else { return Loc.t("InsightsEmpty") }
        if isScanning || fileTypes.isEmpty && ageStats.isEmpty { return Loc.t("InsightsWait") }
        return Loc.f("TypesNote", FileOps.formatCount(fileTypes.count), root.fullPath) + staleNote
    }

    var agesNote: String {
        guard root != nil else { return Loc.t("InsightsEmpty") }
        if isScanning || ageStats.isEmpty { return Loc.t("InsightsWait") }
        return Loc.t("AgesNote") + staleNote
    }

    private var staleNote: String { statsStale ? " " + Loc.t("InsightsStale") : "" }

    /// Liệt kê toàn bộ file của một loại (không chỉ trong 500 file lớn nhất).
    func findType(_ ext: String) {
        guard !ext.isEmpty else { return }
        findText = "*" + ext
        findSizeIndex = 0
        findAgeIndex = 0
        rightTab = .largest
        Task { await runFind() }
    }

    /// Nhóm "1 đến 2 năm" → tìm file cũ hơn 1 năm (lớn nhất trước), để dọn file lâu không dùng.
    func findOlder(bucket: Int) {
        findText = ""
        findSizeIndex = 0
        findAgeIndex = min(max(0, bucket), Self.findAgeDays.count - 1)
        rightTab = .largest
        Task { await runFind() }
    }

    // ================= Tìm file =================

    /// Danh sách đang hiển thị ở tab File lớn nhất: kết quả tìm kiếm hoặc file lớn nhất của lần quét.
    var displayedFiles: [TopFile] { searchResults ?? topFiles }

    var findInfoText: String {
        if let n = findProgress { return Loc.f("FindSearching", FileOps.formatCount(n), root?.fullPath ?? "") }
        if let findError { return Loc.f("FindFailed", findError) }
        guard let results = searchResults else { return Loc.t("FindTopHint") }
        if results.isEmpty { return Loc.t("FindNone") }
        var text = Loc.f("FindResult", FileOps.formatCount(results.count),
                         FileOps.formatSize(results.reduce(Int64(0)) { $0 + $1.size }))
        if searchCapped { text += " " + Loc.f("FindCapped", FileOps.formatCount(Self.maxFindResults)) }
        return text
    }

    func cancelFind() {
        findToken?.cancel()
    }

    /// Quay lại danh sách file lớn nhất của lần quét.
    func clearSearch() {
        cancelFind()
        if searchResults != nil { searchGeneration += 1 }
        searchResults = nil
        searchCapped = false
        findError = nil
        setTopSelection([])
    }

    func runFind() async {
        guard findProgress == nil, let root else { return }
        if isScanning {
            await Dialogs.alert(Loc.t("MsgWaitScan"))
            return
        }
        let patterns = FileFinder.parsePatterns(findText)
        let minSize = Self.findSizes[min(max(0, findSizeIndex), Self.findSizes.count - 1)]
        let days = Self.findAgeDays[min(max(0, findAgeIndex), Self.findAgeDays.count - 1)]
        let olderThan: Double? = days > 0 ? Date().timeIntervalSince1970 - Double(days) * 86_400 : nil
        let path = root.fullPath
        let token = CancelToken()
        findToken = token
        findError = nil
        findProgress = 0

        let counter = FileFinder.Counter()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.findProgress != nil { self?.findProgress = counter.found } }
        }
        RunLoop.main.add(timer, forMode: .common)
        defer {
            timer.invalidate()
            if findToken === token {
                findToken = nil
                findProgress = nil
            }
        }

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try FileFinder.find(root: path, patterns: patterns, minSize: minSize, olderThan: olderThan,
                                    max: AppModel.maxFindResults, counter: counter, isCancelled: { token.isCancelled })
            }.value
            // Đã quét thư mục khác trong lúc tìm
            guard root === self.root else { return }
            setTopSelection([])
            searchGeneration += 1
            searchResults = result.files.map { TopFile(path: $0.path, size: $0.size, modified: $0.modified) }
            searchCapped = result.total > Int64(result.files.count)
            setTopSelection([])
        } catch is CancellationError {
        } catch {
            findError = error.localizedDescription
        }
    }
}
