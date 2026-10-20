import AppKit
import Observation
import DiskatCore

/// Một bản trong nhóm trùng lặp.
@MainActor
@Observable
final class DupFileState: Identifiable {
    let file: DupFile
    unowned let group: DupGroupState
    var isChecked = false

    init(_ file: DupFile, group: DupGroupState) {
        self.file = file
        self.group = group
    }

    nonisolated var id: String { file.path }
    var path: String { file.path }
    var name: String { (file.path as NSString).lastPathComponent }
    var folder: String { (file.path as NSString).deletingLastPathComponent }
    /// Bản có hard link: xóa một tên không giải phóng được chỗ nào nên không cho đánh dấu.
    var canCheck: Bool { !file.isHardLinked }

    var note: String? {
        if file.isHardLinked { return Loc.t("DupHardLink") }
        if file.isClone { return Loc.t("DupClone") }
        return nil
    }

    var tip: String {
        var tip = file.path
        if file.isHardLinked {
            tip += "\n\n" + Loc.f("DupHardLinkTip", FileOps.formatCount(file.linkCount))
            if !file.otherNames.isEmpty { tip += "\n\n" + Loc.t("DupAlsoAt") + "\n" + file.otherNames.joined(separator: "\n") }
        } else if file.isClone {
            tip += "\n\n" + Loc.t("DupCloneTip")
        }
        return tip
    }
}

/// Tiêu đề của một nhóm file giống hệt nhau.
@MainActor
@Observable
final class DupGroupState: Identifiable {
    let id = UUID()
    let size: Int64
    /// Dung lượng giải phóng được theo bộ tìm (đã trừ hard link và bản clone APFS dùng chung dữ liệu)
    private let baseWasted: Int64
    private let baseCount: Int
    var files: [DupFileState] = []
    var isExpanded = true

    init(_ group: DupGroup) {
        size = group.size
        baseWasted = group.wasted
        baseCount = group.files.count
        files = group.files.map { DupFileState($0, group: self) }
    }

    var name: String { files.first?.name ?? "" }

    /// Giải phóng được khi chỉ giữ một bản (hard link và các clone APFS dùng chung dữ liệu được tính như bộ tìm).
    var wasted: Int64 {
        if files.count == baseCount { return baseWasted }
        return DupGroup(size: size, files: files.map(\.file)).wasted
    }

    var checkedCount: Int { files.filter(\.isChecked).count }
    /// Đánh dấu thêm một bản chỉ khi vẫn còn ít nhất một bản khác không bị đánh dấu.
    var canCheckAnother: Bool { files.filter { !$0.isChecked }.count > 1 }
}

/// Trạng thái tab Trùng lặp: tìm file giống hệt nhau trong thư mục đã quét, đánh dấu các bản thừa rồi xóa an toàn
/// (tương ứng MainWindow.Duplicates.cs của bản Windows).
@MainActor
@Observable
final class DuplicatesModel {
    // Đơn vị thập phân giống Finder
    static let sizes: [Int64] = [100_000, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000]
    static let sizeLabels = ["100 KB", "1 MB", "10 MB", "100 MB", "1 GB"]

    var minSizeIndex = 1 // 1 MB
    var skipSystem = true
    private(set) var groups: [DupGroupState]?
    private(set) var result: DupResult?
    private(set) var minLabel = ""
    /// Đang tìm: tiến độ để hiển thị
    private(set) var running = false
    private(set) var progressText = ""
    /// nil: chưa biết tổng (đang liệt kê file)
    private(set) var progressFraction: Double?
    var error: String?
    /// Thông báo tạm (vd. "phải giữ lại ít nhất một bản")
    var notice: String?
    var selection: Set<String> = []
    @ObservationIgnored private var cancelFlag: DuplicateFinder.CancelFlag?
    // Đang xóa nhiều file: gom việc cập nhật danh sách vào một lần ở cuối
    @ObservationIgnored var batch = false
    @ObservationIgnored var dirty = false

    var checkedFiles: [DupFileState] { (groups ?? []).flatMap { $0.files.filter(\.isChecked) } }
    var checkedCount: Int { (groups ?? []).reduce(0) { $0 + $1.checkedCount } }
    var checkedBytes: Int64 { (groups ?? []).reduce(Int64(0)) { $0 + Int64($1.checkedCount) * $1.size } }

    func cancel() {
        cancelFlag?.cancel()
    }

    /// Dừng tìm và bỏ kết quả cũ khi bắt đầu quét thư mục mới.
    func reset() {
        cancel()
        cancelFlag = nil
        running = false
        clearResults()
    }

    private func clearResults() {
        groups = nil
        result = nil
        selection = []
        error = nil
        notice = nil
    }

    func info(root: DirNode?, scanning: Bool) -> String {
        if running { return progressText }
        if let error { return Loc.f("FindFailed", error) }
        guard let root else { return Loc.t("DupEmpty") }
        if scanning { return Loc.t("InsightsWait") }
        guard let groups, let result else { return Loc.f("DupHint", root.fullPath) }
        var text = groups.isEmpty ? Loc.f("DupNone", minLabel)
            : Loc.f("DupResult", FileOps.formatCount(groups.count), FileOps.formatSize(groups.reduce(Int64(0)) { $0 + $1.wasted }))
        if result.cloudSkipped > 0 { text += " " + Loc.f("DupSkippedCloud", FileOps.formatCount(result.cloudSkipped)) }
        if result.unreadable > 0 { text += " " + Loc.f("DupUnreadable", FileOps.formatCount(result.unreadable)) }
        return text
    }

    var selectionInfo: String {
        if let notice { return notice }
        let n = checkedCount
        return n == 0 ? Loc.t("DupSelNone") : Loc.f("DupSelInfo", FileOps.formatCount(n), FileOps.formatSize(checkedBytes))
    }

    // ================= Tìm =================

    func run(root: DirNode) async {
        guard !running else { return }
        let index = min(max(0, minSizeIndex), Self.sizes.count - 1)
        let minSize = Self.sizes[index], skip = skipSystem, path = root.fullPath
        clearResults()
        let flag = DuplicateFinder.CancelFlag()
        cancelFlag = flag
        running = true
        let progress = DuplicateFinder.Progress()
        func show() {
            let done = progress.done, total = progress.total
            switch progress.stage {
            case 0:
                progressText = Loc.f("DupListing", FileOps.formatCount(progress.found), path)
                progressFraction = nil
            case 1:
                progressText = Loc.f("DupHead", FileOps.formatCount(done), FileOps.formatCount(total))
                progressFraction = total > 0 ? Double(done) / Double(total) : 0
            default:
                progressText = Loc.f("DupFull", FileOps.formatSize(done), FileOps.formatSize(total))
                progressFraction = total > 0 ? Double(done) / Double(total) : 1
            }
        }
        show()
        let timer = Timer(timeInterval: 0.2, repeats: true) { _ in MainActor.assumeIsolated { show() } }
        RunLoop.main.add(timer, forMode: .common)
        defer {
            timer.invalidate()
            if cancelFlag === flag {
                cancelFlag = nil
                running = false
            }
        }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try DuplicateFinder.find(root: path, minSize: minSize, skipSystem: skip, progress: progress, cancel: flag)
            }.value
            // Đã quét thư mục khác trong lúc tìm
            guard root === AppModel.shared.root, !flag.isCancelled else { return }
            self.result = result
            minLabel = Self.sizeLabels[index]
            // Nhóm chỉ gồm các clone APFS của nhau (thường là thư mục build): xóa bản nào cũng không lấy lại được chỗ
            groups = result.groups.filter { $0.wasted > 0 }.map(DupGroupState.init)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    // ================= Đánh dấu =================

    /// Không cho đánh dấu bản cuối cùng của nhóm (luôn giữ lại ít nhất một bản).
    func setChecked(_ file: DupFileState, _ value: Bool) {
        notice = nil
        if value && (!file.canCheck || !file.group.canCheckAnother) {
            notice = Loc.t("DupKeepOne")
            AppModel.shared.setStatus { Loc.t("DupKeepOne") }
            return
        }
        file.isChecked = value
    }

    /// Mỗi nhóm: đánh dấu mọi bản trừ bản sửa gần nhất. Bản có hard link không bao giờ được đánh dấu.
    func selectAllButNewest() {
        notice = nil
        for g in groups ?? [] {
            // Danh sách đã xếp mới nhất trước
            guard let keep = g.files.max(by: { $0.file.modified < $1.file.modified }) else { continue }
            for f in g.files { f.isChecked = f !== keep && f.canCheck }
        }
    }

    func clearChecks() {
        notice = nil
        for g in groups ?? [] { for f in g.files where f.isChecked { f.isChecked = false } }
    }

    func toggleSelected() {
        for id in selection {
            if let f = file(id) { setChecked(f, !f.isChecked) }
            else if selection.count == 1, let g = groups?.first(where: { "g:" + $0.id.uuidString == id }) { g.isExpanded.toggle() }
        }
    }

    func file(_ path: String) -> DupFileState? {
        for g in groups ?? [] { if let f = g.files.first(where: { $0.path == path }) { return f } }
        return nil
    }

    /// File được chọn trong danh sách (dòng tiêu đề nhóm: bản đầu tiên của nhóm).
    var selectedFiles: [DupFileState] {
        var out: [DupFileState] = []
        for id in selection {
            if let f = file(id) { out.append(f) }
            else if let g = groups?.first(where: { "g:" + $0.id.uuidString == id }), let f = g.files.first { out.append(f) }
        }
        return out
    }

    // ================= Gỡ file đã xóa =================

    /// Gỡ các file thỏa điều kiện khỏi kết quả (khi chúng bị xóa ở bất kỳ đâu trong app).
    func removeWhere(_ gone: (String) -> Bool) {
        guard var list = groups else { return }
        var changed = false
        for g in list {
            let before = g.files.count
            g.files.removeAll { gone($0.path) }
            if g.files.count != before { changed = true }
        }
        guard changed else { return }
        // Nhóm chỉ còn một bản, hoặc không còn bản nào xóa được, thì không còn là trùng lặp
        list.removeAll { $0.files.count < 2 || $0.files.allSatisfy { !$0.canCheck } }
        groups = list
        if batch { dirty = true } else { afterGroupsChanged() }
    }

    func afterGroupsChanged() {
        dirty = false
        for g in groups ?? [] where g.files.allSatisfy(\.isChecked) {
            // Bản giữ lại đã mất: bỏ đánh dấu cả nhóm để không bao giờ xóa hết
            for f in g.files { f.isChecked = false }
        }
        let groupIDs = Set((groups ?? []).map { "g:" + $0.id.uuidString })
        selection = selection.filter { file($0) != nil || groupIDs.contains($0) }
    }
}

/// Xóa các bản đã đánh dấu ở tab Trùng lặp: dùng cùng luồng xác nhận / xóa / cập nhật cây như các tab khác.
extension AppModel {
    /// File vẫn đúng như lúc so sánh (cùng dung lượng và thời điểm sửa): nội dung coi như không đổi.
    /// Trả về dung lượng thực chiếm trên đĩa (để trừ khỏi cây), nil nếu đã đổi hoặc không còn.
    private func unchangedAllocated(_ f: DupFileState) -> Int64? {
        var st = stat()
        guard lstat(f.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, Int64(st.st_size) == f.group.size else { return nil }
        let modified = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
        guard abs(modified - f.file.modified) < 0.000_01 else { return nil }
        return Int64(st.st_blocks) * 512
    }

    func deleteDuplicates(permanent: Bool) async {
        let dup = duplicates
        guard let groups = dup.groups, root != nil, dup.checkedCount > 0, await canStartDelete() else { return }

        // Kiểm tra lại ngay trước khi xóa: nhóm phải còn ít nhất một bản không đánh dấu và chưa bị đổi,
        // bản sẽ xóa cũng phải còn nguyên như lúc so sánh. Không bao giờ xóa hết mọi bản của một nhóm.
        var files: [(file: DupFileState, allocated: Int64)] = []
        var skipped = 0
        for g in groups {
            let chosen = g.files.filter(\.isChecked)
            guard !chosen.isEmpty else { continue }
            let keepOk = chosen.count < g.files.count && g.files.contains { !$0.isChecked && unchangedAllocated($0) != nil }
            for f in chosen {
                if keepOk, f.canCheck, let allocated = unchangedAllocated(f) { files.append((f, allocated)) }
                else { skipped += 1 }
            }
        }
        if files.isEmpty {
            await Dialogs.alert(Loc.f("DupChanged", FileOps.formatCount(skipped)))
            return
        }
        for (f, _) in files {
            if let reason = FileOps.protectionReason(f.path) {
                await Dialogs.alert(Loc.t("MsgNotAllowed"), detail: "\(reason)\n\n\(f.path)", style: .critical)
                return
            }
        }

        let total = files.reduce(Int64(0)) { $0 + $1.file.group.size }
        let label = files.count == 1 ? files[0].file.path : Loc.f("SelectedFiles", files.count)
        let warning = skipped > 0 ? Loc.f("DupChanged", FileOps.formatCount(skipped)) : nil

        isBusy = true
        dup.batch = true
        dup.dirty = false
        defer {
            dup.batch = false
            if dup.dirty { dup.afterGroupsChanged() }
            isBusy = false
        }
        guard await confirmDelete(what: files.count == 1 ? Loc.t("WhatFile") : Loc.f("WhatFiles", files.count), path: label,
                                  size: total, detail: Loc.t("DupConfirmDetail"), permanent: permanent, warning: warning) else { return }

        var freed: Int64 = 0
        for (f, allocated) in files {
            // Bản giữ lại có thể đã bị xóa ở nơi khác trong lúc hộp thoại đang mở
            guard f.group.files.contains(where: { !$0.isChecked && FileOps.exists($0.path) }) else { continue }
            if !(await runDelete(f.path, permanent: permanent)) { break }
            if FileOps.exists(f.path) { break }

            freed += allocated
            if let owner = findNode(f.folder) { applyFileRemoved(owner: owner, row: nil, size: allocated) }
            statsStale = true
            removeTopFiles(under: f.path) // cũng gỡ khỏi danh sách trùng lặp
        }

        afterTreeChanged(selectingRow: tree?.selectedRowIndex ?? 0)
        if freed > 0 {
            let text = FileOps.formatSize(freed)
            setStatus { Loc.f("FreedShort", text) }
        }
    }
}
