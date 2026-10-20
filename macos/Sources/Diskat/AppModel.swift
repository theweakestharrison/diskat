import AppKit
import Observation
import DiskatCore

enum RightTab: Hashable { case map, largest }
enum ActivePane { case tree, largest }
enum SortKey: String { case name, size, files, dirs, date }

/// Một file (hoặc dòng tóm tắt "… và N file nhỏ hơn") trong cây thư mục.
final class FileRow {
    enum Kind { case file, summary }

    let kind: Kind
    /// Thư mục chứa
    let owner: DirNode
    let name: String
    let size: Int64
    let modified: Double
    /// Số file được gộp (dòng tóm tắt)
    let count: Int

    init(file: FileItem, owner: DirNode) {
        kind = .file
        self.owner = owner
        name = file.name
        size = file.size
        modified = file.modified
        count = 1
    }

    init(summaryOf owner: DirNode, count: Int, size: Int64) {
        kind = .summary
        self.owner = owner
        name = ""
        self.size = size
        modified = 0
        self.count = count
    }

    var fullPath: String { kind == .file ? FileOps.join(owner.fullPath, name) : owner.fullPath }
    var displayName: String { kind == .summary ? Loc.f("MoreFiles", FileOps.formatCount(count)) : name }
}

struct TopFile: Identifiable, Hashable {
    let path: String
    let size: Int64
    let modified: Double

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
}

/// Yêu cầu xác nhận xóa đang hiển thị (sheet). `resolve` chỉ có tác dụng ở lần gọi đầu.
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let permanent: Bool
    let what: String
    let path: String
    let size: String
    let detail: String
    let warning: String?
    let resolve: (Bool) -> Void
}

/// Trạng thái và logic của cửa sổ chính (tương ứng MainWindow.*.cs của bản Windows).
/// Cây thư mục và bản đồ là view AppKit; model gọi trực tiếp vào chúng qua `tree` / `map`.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    static let maxFilesPerFolder = 1000

    // ================= Quét =================

    @ObservationIgnored private(set) var scanner: DiskScanner?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var scanStart = ContinuousClock.now
    @ObservationIgnored private var scanEnd: ContinuousClock.Instant?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tick = 0

    private(set) var root: DirNode?
    private(set) var isScanning = false
    var isRescanning = false
    /// Đang xóa / quét lại một thư mục: chỉ một thao tác tại một thời điểm
    var isBusy = false
    /// Lớp phủ khi đang xóa
    var busyText: String?
    var pathText = ""
    var pathFieldFocused = false
    /// Dòng trạng thái dưới dạng hàm để có thể dịch lại khi đổi ngôn ngữ
    private(set) var status: () -> String = { Loc.t("Ready") }
    /// Tăng mỗi khi số liệu (dung lượng, số file...) thay đổi để các nhãn phụ thuộc được vẽ lại
    private(set) var valuesRevision = 0

    // ================= Cây =================

    @ObservationIgnored weak var tree: TreeController?
    private(set) var selection: AnyObject?
    private(set) var sortKey: SortKey = .size
    private(set) var sortDescending = true
    // Giữ tham chiếu mạnh tới thư mục để ObjectIdentifier không bị dùng lại khi còn trong bộ đệm
    @ObservationIgnored private var childCache: [ObjectIdentifier: (owner: DirNode, items: [AnyObject])] = [:]
    @ObservationIgnored private var fileRowCache: [ObjectIdentifier: (owner: DirNode, rows: [FileRow])] = [:]

    // ================= Bản đồ =================

    @ObservationIgnored weak var map: TreemapView? {
        didSet { map?.setRoot(mapRoot) }
    }
    private(set) var mapRoot: DirNode?
    var mapHoverText: String?
    /// True khi ô vừa nhấp trên bản đồ khớp đúng một dòng trong cây. Nếu không (ô "[N file]",
    /// "[N mục khác]", file ngoài danh sách) thì không mở menu chuột phải để tránh xóa nhầm cả thư mục chứa.
    @ObservationIgnored private(set) var mapClickExact = false
    @ObservationIgnored private var selectingFromMap = false

    // ================= File lớn nhất =================

    var topFiles: [TopFile] = []
    var topSelection: Set<String> = []
    var rightTab: RightTab = .map
    var activePane: ActivePane = .tree

    // ================= Khác =================

    private(set) var volumes: [VolumeInfo] = []
    private(set) var hasFullDiskAccess = true
    var confirm: ConfirmRequest?

    private init() {}

    func launched() {
        loadVolumes()
        refreshFullDiskAccess()
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.loadVolumes() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFullDiskAccess()
                self?.loadVolumes()
            }
        }
        // Diskat /đường/dẫn hoặc: open -a Diskat --args /đường/dẫn
        if let arg = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") && FileOps.isDirectory($0) }) {
            startScan(arg)
        }
        #if DEBUG
        DebugHooks.install(self)
        #endif
    }

    // ================= Ngôn ngữ =================

    func setStatus(_ text: @escaping () -> String) {
        status = text
    }

    func bumpValues() {
        valuesRevision += 1
    }

    func setLanguage(_ code: String) {
        Loc.setLanguage(code)
        tree?.applyLanguage()
        map?.redraw()
        mapHoverText = nil
        valuesRevision += 1
    }

    // ================= Ổ đĩa / quyền =================

    func loadVolumes() {
        volumes = Volumes.mounted()
    }

    func refreshFullDiskAccess() {
        // TCC.db chỉ đọc được khi app có quyền Full Disk Access; thiếu file thì coi như có quyền (không làm phiền)
        let fd = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if fd >= 0 {
            close(fd)
            hasFullDiskAccess = true
        } else {
            hasFullDiskAccess = errno != EPERM && errno != EACCES
        }
    }

    func requestFullDiskAccess() {
        Task {
            let r = await Dialogs.alert(Loc.t("FdaTitle"), detail: Loc.t("FdaBody"), buttons: [Loc.t("FdaOpen"), Loc.t("Cancel")])
            if r == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // ================= Quét =================

    func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = Loc.t("BrowseTitle")
        panel.prompt = Loc.t("Scan")
        let current = FileOps.resolvedPath(pathText)
        if !pathText.isEmpty && FileOps.isDirectory(current) { panel.directoryURL = URL(fileURLWithPath: current) }
        if panel.runModal() == .OK, let url = panel.url {
            pathText = url.path
            startScan(url.path)
        }
    }

    func scanFromField() {
        let p = pathText.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if p.isEmpty { browse(); return }
        startScan(p)
    }

    func stopScan() { scanner?.cancel() }

    func startScan(_ input: String) {
        Task { await startScanAsync(input) }
    }

    func startScanAsync(_ input: String) async {
        if isBusy {
            await Dialogs.alert(Loc.t("MsgBusy"))
            return
        }
        let path = FileOps.resolvedPath(input)
        // Cùng một thư mục được yêu cầu hai lần lúc khởi động (đối số dòng lệnh + sự kiện mở file)
        if isScanning, scanner?.root.fullPath == path { return }
        guard FileOps.isDirectory(path) else {
            await Dialogs.alert(Loc.f("MsgNotFound", input), style: .warning)
            return
        }

        if let old = scanner, isScanning {
            old.cancel()
            await scanTask?.value
        }
        // Trong lúc chờ, một yêu cầu khác có thể đã bắt đầu quét: hủy luôn, lần quét đó tự dừng nhờ scanGeneration
        if isScanning { scanner?.cancel() }

        scanGeneration += 1
        let generation = scanGeneration
        let sc = DiskScanner(path: path)
        scanner = sc
        root = sc.root
        sc.root.isExpanded = true
        pathText = sc.root.fullPath

        selection = nil
        childCache.removeAll()
        fileRowCache.removeAll()
        topFiles = []
        topSelection = []
        tree?.reload()
        setMapRoot(sc.root)

        setScanning(true)
        scanStart = .now
        scanEnd = nil
        tick = 0
        startTimer()

        let task = Task { await sc.run() }
        scanTask = task
        await task.value

        // Một lần quét mới đã bắt đầu trong lúc chờ: để lần đó xử lý
        guard generation == scanGeneration else { return }
        stopTimer()
        scanEnd = .now
        setScanning(false)
        onScanFinished(cancelled: sc.isCancelled)
    }

    private func setScanning(_ scanning: Bool) {
        isScanning = scanning
        valuesRevision += 1
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func onTick() {
        guard let sc = scanner else { return }
        tick += 1
        let current = sc.currentPath ?? sc.root.fullPath
        status = { Loc.f("Scanning", current) }

        // Sắp xếp lại mỗi giây để thư mục nặng nhất nổi lên đầu ngay trong lúc quét
        if tick % 5 == 0 {
            rebuildTree()
            map?.redraw()
        } else {
            tree?.refreshVisible()
        }
        valuesRevision += 1
    }

    var scanSeconds: Double {
        let end = scanEnd ?? .now
        let d = scanStart.duration(to: end)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    var statsText: String {
        _ = valuesRevision
        guard let root, let sc = scanner else { return "" }
        let blocked = sc.errors > 0 ? Loc.f("StatsBlocked", FileOps.formatCount(sc.errors)) : ""
        return Loc.f("Stats", FileOps.formatSize(root.size), FileOps.formatCount(root.fileCount),
                     FileOps.formatCount(root.dirCount), scanSeconds) + blocked
    }

    private func onScanFinished(cancelled: Bool) {
        guard let root, let sc = scanner else { return }
        rebuildTree()
        setMapRoot(mapRoot ?? root)
        loadTopFiles()

        let secs = scanSeconds
        let rate = FileOps.formatCount(Int64(Double(root.fileCount) / max(secs, 0.001)))
        let hint = sc.errors > 0 && !hasFullDiskAccess
        status = {
            cancelled ? Loc.f("ScanStopped", secs)
                : Loc.f("ScanDone", secs, rate) + (hint ? Loc.t("ScanDoneBlocked") : "")
        }
        if selection == nil { tree?.selectRow(0) }
        tree?.focus()
        valuesRevision += 1
    }

    // ================= Dữ liệu cây =================

    /// Các dòng con của một mục trong cây (nil = gốc), đã sắp xếp: thư mục con + file trực tiếp.
    func children(of item: Any?) -> [AnyObject] {
        guard let root else { return [] }
        guard let dir = item as? DirNode else { return item == nil ? [root] : [] }
        // Chưa quét xong thì luôn rỗng: số lượng và từng phần tử NSOutlineView hỏi phải khớp nhau
        guard !dir.isMount, dir.isScanned else { return [] }
        let key = ObjectIdentifier(dir)
        if let cached = childCache[key] { return cached.items }
        var items: [AnyObject] = dir.children
        items.append(contentsOf: fileRows(of: dir) as [AnyObject])
        let sorted = sortItems(items)
        childCache[key] = (dir, sorted)
        return sorted
    }

    func isExpandable(_ item: Any) -> Bool {
        guard let d = item as? DirNode, !d.isMount else { return false }
        return !d.isScanned || !d.children.isEmpty || d.ownFiles > 0
    }

    func fileRows(of dir: DirNode) -> [FileRow] {
        let key = ObjectIdentifier(dir)
        if let cached = fileRowCache[key] { return cached.rows }
        guard dir.isScanned else { return [] } // chưa quét xong thì chưa cache

        var rows: [FileRow] = []
        if dir.ownFiles > 0 {
            var files = FileOps.listFiles(dir.fullPath)
            files.sort { $0.size > $1.size }
            let n = min(files.count, Self.maxFilesPerFolder)
            rows = files[..<n].map { FileRow(file: $0, owner: dir) }
            if files.count > n {
                let rest = files[n...].reduce(Int64(0)) { $0 + $1.size }
                rows.append(FileRow(summaryOf: dir, count: files.count - n, size: rest))
            }
        }
        fileRowCache[key] = (dir, rows)
        return rows
    }

    func fileRowCacheRemove(_ dir: DirNode, keeping row: FileRow? = nil) {
        let key = ObjectIdentifier(dir)
        if let row, var entry = fileRowCache[key] {
            entry.rows.removeAll { $0 === row }
            fileRowCache[key] = entry
        } else {
            fileRowCache[key] = nil
        }
    }

    func fileRowCacheRemoveAll() {
        fileRowCache.removeAll()
    }

    /// Xóa bộ đệm danh sách con rồi nạp lại cây (giữ dòng đang chọn và vị trí cuộn).
    func rebuildTree() {
        childCache.removeAll()
        tree?.reload()
    }

    func setSort(_ key: SortKey, descending: Bool) {
        sortKey = key
        sortDescending = descending
        rebuildTree()
    }

    private struct SortEntry {
        let group: Int
        let number: Double
        let name: String
        let item: AnyObject
    }

    private func sortEntry(_ item: AnyObject) -> SortEntry {
        if let d = item as? DirNode {
            let n: Double = switch sortKey {
            case .size: Double(d.size)
            case .files: Double(d.fileCount)
            case .dirs: Double(d.dirCount)
            case .date: d.modified
            case .name: 0
            }
            return SortEntry(group: 0, number: n, name: d.name, item: d)
        }
        let f = item as! FileRow
        if f.kind == .summary {
            let n: Double = switch sortKey {
            case .files: Double(f.count)
            case .size: Double(f.size)
            default: -1
            }
            return SortEntry(group: 2, number: n, name: "", item: f)
        }
        let n: Double = switch sortKey {
        case .size: Double(f.size)
        case .files: 1
        case .dirs: -1
        case .date: f.modified
        case .name: 0
        }
        return SortEntry(group: sortKey == .name ? 1 : 0, number: n, name: f.name, item: f)
    }

    private func sortItems(_ items: [AnyObject]) -> [AnyObject] {
        guard items.count > 1 else { return items }
        // Chụp nhanh khóa trước khi sắp xếp vì dung lượng có thể thay đổi trong lúc quét
        let entries = items.map(sortEntry)
        let byName = sortKey == .name
        let desc = sortDescending
        return entries.sorted { a, b in
            if a.group != b.group { return a.group < b.group }
            if byName {
                let c = a.name.localizedStandardCompare(b.name)
                return desc ? c == .orderedDescending : c == .orderedAscending
            }
            if a.number != b.number { return desc ? a.number > b.number : a.number < b.number }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }.map(\.item)
    }

    func collapseAll() {
        guard let root else { return }
        var stack = [root]
        while let n = stack.popLast() {
            guard n.isExpanded else { continue }
            n.isExpanded = false
            stack.append(contentsOf: n.children)
        }
        root.isExpanded = true
        tree?.collapseAll()
        rebuildTree()
        tree?.selectRow(0)
    }

    // ================= Chọn =================

    var selectedDir: DirNode? { selection as? DirNode }
    var selectedFile: FileRow? { (selection as? FileRow).flatMap { $0.kind == .file ? $0 : nil } }
    var selectedPath: String? { selectedDir?.fullPath ?? selectedFile?.fullPath }
    var hasSelection: Bool { selectedDir != nil || selectedFile != nil }
    var canDeleteSelection: Bool { hasSelection && !isBusy && !isScanning && selectedDir !== root }

    var selectionText: String {
        _ = valuesRevision
        if let d = selectedDir {
            return "\(d.fullPath)  ·  \(FileOps.formatSize(d.size))" + Loc.f("SelFiles", FileOps.formatCount(d.fileCount))
        }
        if let f = selection as? FileRow {
            return "\(f.fullPath)  ·  \(FileOps.formatSize(f.size))"
        }
        return root?.fullPath ?? Loc.t("NoSelection")
    }

    /// Gọi từ cây khi dòng được chọn thay đổi. `follow`: bản đồ chuyển tới thư mục được chọn.
    func treeSelectionChanged(_ item: AnyObject?, follow: Bool) {
        selection = item
        guard follow, !selectingFromMap else { return }
        let target = (item as? DirNode) ?? (item as? FileRow)?.owner
        if let target, !target.isMount, target !== mapRoot {
            setMapRoot(target)
        }
    }

    // ================= Bản đồ =================

    func setMapRoot(_ node: DirNode?) {
        mapRoot = node
        map?.setRoot(node)
        mapHoverText = nil
    }

    var canMapUp: Bool {
        guard let m = mapRoot, let root else { return false }
        return m !== root && m.parent != nil
    }

    func mapUp() {
        guard canMapUp, let parent = mapRoot?.parent else { return }
        setMapRoot(parent)
    }

    func mapClicked(_ item: TreemapView.Item) {
        mapClickExact = false
        selectingFromMap = true
        defer { selectingFromMap = false }
        if let node = item.node {
            if tree?.reveal(node) == true { mapClickExact = true }
            return
        }
        guard tree?.reveal(item.owner) == true else { return }
        guard let path = item.filePath else { return }
        tree?.expand(item.owner)
        let name = (path as NSString).lastPathComponent
        if let row = fileRows(of: item.owner).first(where: { $0.kind == .file && $0.name == name }), tree?.reveal(row) == true {
            mapClickExact = true
        }
    }

    func mapDoubleClicked(_ item: TreemapView.Item) {
        if let node = item.node, !node.isMount, !node.children.isEmpty || node.ownFiles > 0 {
            setMapRoot(node)
        } else if let path = item.filePath {
            Finder.reveal(path)
        }
    }

    func mapHovered(_ item: TreemapView.Item?) {
        guard let item else { mapHoverText = nil; return }
        let total = mapRoot?.size ?? 0
        let pct = total > 0 ? Double(item.size) * 100 / Double(total) : 0
        let path = item.node?.fullPath ?? item.filePath ?? item.owner.fullPath
        mapHoverText = "\(item.label)  ·  \(FileOps.formatSize(item.size))  ·  \(String(format: "%.1f", pct))%  ·  \(path)"
    }
}
