import AppKit
import SwiftUI
import DiskatCore

/// Cây thư mục: NSOutlineView (ảo hóa sẵn, có ←/→ để mở/đóng) bọc cho SwiftUI.
struct FolderTree: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> TreeController { TreeController(model: model) }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeView() }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

final class FillingScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func tile() {
        super.tile()
        onLayout?()
    }
}

final class DiskatOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?
    var onFocus: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Return / Enter: mở hoặc đóng thư mục
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?()
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Chuột phải: chọn dòng đó trước để menu thao tác trên đúng mục
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !isRowSelected(row) { selectRowIndexes([row], byExtendingSelection: false) }
        onFocus?()
        return super.menu(for: event)
    }
}

@MainActor
final class TreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let model: AppModel
    private let outline = DiskatOutlineView()
    private let scroll = FillingScrollView()
    /// Đang nạp lại dữ liệu: thay đổi dòng chọn khi đó không làm bản đồ đổi theo
    private var suppress = false

    private struct Column {
        let id: String
        let titleKey: String
        let width: CGFloat
        let minWidth: CGFloat
        let ascending: Bool
    }

    private static let columns = [
        Column(id: "name", titleKey: "ColName", width: 260, minWidth: 160, ascending: true),
        Column(id: "size", titleKey: "ColSize", width: 90, minWidth: 60, ascending: false),
        Column(id: "pct", titleKey: "ColPercent", width: 122, minWidth: 90, ascending: false),
        Column(id: "files", titleKey: "ColFiles", width: 72, minWidth: 50, ascending: false),
        Column(id: "dirs", titleKey: "ColFolders", width: 66, minWidth: 50, ascending: false),
        Column(id: "date", titleKey: "ColModified", width: 122, minWidth: 80, ascending: false),
    ]

    // Cột "Thay đổi": chỉ có khi đang so sánh với một lần quét đã lưu
    private static let changeColumn = Column(id: "change", titleKey: "ColChange", width: 90, minWidth: 64, ascending: false)

    init(model: AppModel) {
        self.model = model
    }

    /// Hiện / ẩn cột "Thay đổi" (ngay sau cột Dung lượng) theo trạng thái so sánh, rồi nạp lại cây.
    func applyComparison(_ comparing: Bool) {
        let id = NSUserInterfaceItemIdentifier(Self.changeColumn.id)
        let existing = outline.tableColumn(withIdentifier: id)
        if comparing && existing == nil {
            let c = Self.changeColumn
            let col = NSTableColumn(identifier: id)
            col.width = c.width
            col.minWidth = c.minWidth
            col.title = Loc.t(c.titleKey)
            col.headerCell.alignment = .right
            col.sortDescriptorPrototype = NSSortDescriptor(key: c.id, ascending: c.ascending)
            outline.addTableColumn(col)
            let size = outline.column(withIdentifier: NSUserInterfaceItemIdentifier("size"))
            if size >= 0 { outline.moveColumn(outline.numberOfColumns - 1, toColumn: min(size + 1, outline.numberOfColumns - 1)) }
        } else if !comparing, let existing {
            outline.removeTableColumn(existing)
            if model.sortKey == .change {
                outline.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
            }
        }
        fitNameColumn()
        reload()
    }

    func makeView() -> NSScrollView {
        for c in Self.columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(c.id))
            col.width = c.width
            col.minWidth = c.minWidth
            col.sortDescriptorPrototype = NSSortDescriptor(key: c.id, ascending: c.ascending)
            if c.id != "name" {
                col.headerCell.alignment = c.id == "pct" || c.id == "date" ? .left : .right
            }
            outline.addTableColumn(col)
            if c.id == "name" { outline.outlineTableColumn = col }
        }
        outline.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
        outline.headerView = NSTableHeaderView()
        outline.style = .fullWidth
        outline.rowHeight = 24
        outline.intercellSpacing = NSSize(width: 8, height: 0)
        outline.indentationPerLevel = 14
        outline.autoresizesOutlineColumn = false
        // Cột "Tên" lấp phần còn lại (fitNameColumn), các cột số giữ nguyên độ rộng
        outline.columnAutoresizingStyle = .noColumnAutoresizing
        outline.allowsColumnReordering = false
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.usesAlternatingRowBackgroundColors = true
        outline.backgroundColor = .controlBackgroundColor
        outline.autosaveName = "TreeColumns"
        outline.autosaveTableColumns = true
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        outline.onReturn = { [weak self] in self?.toggleSelected() }
        outline.onFocus = { [weak self] in self?.model.setActivePane(.tree) }

        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        scroll.onLayout = { [weak self] in self?.fitNameColumn() }
        NotificationCenter.default.addObserver(forName: NSTableView.columnDidResizeNotification, object: outline, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                let col = n.userInfo?["NSTableColumn"] as? NSTableColumn
                if col?.identifier.rawValue != "name" { self?.fitNameColumn() }
            }
        }
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        applyLanguage()
        model.tree = self
        reload()
        return scroll
    }

    /// Cột "Tên" chiếm phần chiều rộng còn lại để các cột số luôn nằm trong khung nhìn.
    private func fitNameColumn() {
        guard let name = outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name")) else { return }
        let others = outline.tableColumns.filter { $0 !== name }.reduce(0) { $0 + $1.width }
        let spacing = outline.intercellSpacing.width * CGFloat(outline.numberOfColumns)
        let width = max(name.minWidth, scroll.contentView.bounds.width - others - spacing)
        if abs(name.width - width) > 0.5 { name.width = width }
    }

    // ================= Nạp dữ liệu =================

    /// Nạp lại toàn bộ (sau khi sắp xếp / xóa / quét lại) nhưng giữ dòng đang chọn, trạng thái mở và vị trí cuộn.
    func reload() {
        let selected = model.selection
        let origin = scroll.contentView.bounds.origin
        suppress = true
        defer { suppress = false }
        outline.reloadData()
        syncExpansion(of: nil)
        if let selected, case let row = outline.row(forItem: selected), row >= 0 {
            outline.selectRowIndexes([row], byExtendingSelection: false)
        } else {
            outline.deselectAll(nil)
        }
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Mở/đóng các dòng theo `DirNode.isExpanded` (chỉ đi vào các thư mục đang mở).
    private func syncExpansion(of item: Any?) {
        for child in model.children(of: item) {
            guard let node = child as? DirNode, model.isExpandable(node) else { continue }
            if node.isExpanded {
                if !outline.isItemExpanded(node) { outline.expandItem(node) }
                syncExpansion(of: node)
            } else if outline.isItemExpanded(node) {
                outline.collapseItem(node)
            }
        }
    }

    /// Cập nhật số liệu của các dòng đang hiển thị (gọi 5 lần/giây khi đang quét).
    func refreshVisible() {
        let range = outline.rows(in: outline.visibleRect)
        guard range.length > 0 else { return }
        outline.reloadData(forRowIndexes: IndexSet(integersIn: range.location..<(range.location + range.length)),
                           columnIndexes: IndexSet(integersIn: 0..<outline.numberOfColumns))
    }

    func applyLanguage() {
        for c in Self.columns + [Self.changeColumn] {
            outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(c.id))?.title = Loc.t(c.titleKey)
        }
        outline.headerView?.needsDisplay = true
        if outline.numberOfRows > 0 {
            outline.reloadData(forRowIndexes: IndexSet(integersIn: 0..<outline.numberOfRows),
                               columnIndexes: IndexSet(integersIn: 0..<outline.numberOfColumns))
        }
    }

    // ================= Điều khiển từ model =================

    var selectedRowIndex: Int { max(0, outline.selectedRow) }

    func selectRow(_ index: Int) {
        guard outline.numberOfRows > 0 else { return }
        let row = min(max(0, index), outline.numberOfRows - 1)
        outline.selectRowIndexes([row], byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    func focus() {
        outline.window?.makeFirstResponder(outline)
    }

    func expand(_ node: DirNode) {
        if !outline.isItemExpanded(node) { outline.expandItem(node) }
    }

    func collapseAll() {
        outline.collapseItem(nil, collapseChildren: true)
    }

    /// Mở các thư mục cha cần thiết, chọn và cuộn tới mục. False nếu mục không nằm trong cây.
    @discardableResult
    func reveal(_ item: AnyObject) -> Bool {
        var chain: [DirNode] = []
        var p = (item as? DirNode)?.parent ?? (item as? FileRow)?.owner
        while let n = p {
            chain.append(n)
            p = n.parent
        }
        if let root = model.root, item !== root, chain.last !== root { return false }
        for n in chain.reversed() { expand(n) }
        let row = outline.row(forItem: item)
        guard row >= 0 else { return false }
        outline.selectRowIndexes([row], byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        return true
    }

    private func toggleSelected() {
        guard outline.selectedRow >= 0, let node = outline.item(atRow: outline.selectedRow) as? DirNode,
              model.isExpandable(node) else { return }
        if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
    }

    @objc private func doubleClicked() {
        let row = outline.clickedRow
        guard row >= 0 else { return }
        let item = outline.item(atRow: row)
        if let node = item as? DirNode {
            guard model.isExpandable(node) else { return }
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else if let file = item as? FileRow, file.kind == .file {
            Finder.reveal(file.fullPath)
        }
    }

    // ================= Data source =================

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        model.children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        model.children(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        model.isExpandable(item)
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let d = outlineView.sortDescriptors.first, let key = d.key else { return }
        // "% thư mục cha" sắp theo dung lượng
        let sort = key == "pct" ? SortKey.size : SortKey(rawValue: key) ?? .size
        model.setSort(sort, descending: !d.ascending)
    }

    // ================= Delegate =================

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? DirNode else { return }
        node.isExpanded = true
        // Thư mục con đã mở trước khi thu gọn cha thì mở lại như cũ
        syncExpansion(of: node)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? DirNode else { return }
        node.isExpanded = false
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outline.selectedRow
        let item = row >= 0 ? outline.item(atRow: row) as AnyObject? : nil
        model.treeSelectionChanged(item, follow: !suppress)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let info = RowInfo(item: item as AnyObject, model: model)
        switch id {
        case "name":
            let cell = reuse(id) { NameCell(frame: .zero) }
            cell.configure(info)
            return cell
        case "change":
            let cell = reuse(id) { TextCell(frame: .zero) }
            let color: NSColor = info.changeSign > 0 ? Theme.growNS : info.changeSign < 0 ? Theme.shrinkNS : .secondaryLabelColor
            cell.configure(info.changeText, alignment: .right, bold: true, color: color)
            cell.toolTip = info.changeTip
            return cell
        case "pct":
            let cell = reuse(id) { PercentCell(frame: .zero) }
            cell.configure(percent: info.percent, color: info.isRoot ? Theme.accentNS : Theme.barColor(percent: info.percent))
            return cell
        default:
            let cell = reuse(id) { TextCell(frame: .zero) }
            switch id {
            case "size": cell.configure(info.sizeText, alignment: .right, bold: true)
            case "files": cell.configure(info.filesText, alignment: .right)
            case "dirs": cell.configure(info.foldersText, alignment: .right)
            default: cell.configure(info.modifiedText, alignment: .left)
            }
            return cell
        }
    }

    private func reuse<T: NSView>(_ id: String, make: () -> T) -> T {
        let identifier = NSUserInterfaceItemIdentifier(id)
        if let v = outline.makeView(withIdentifier: identifier, owner: nil) as? T { return v }
        let v = make()
        v.identifier = identifier
        return v
    }

    // ================= Menu chuột phải =================

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in ContextMenus.tree(model).items {
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }
}

/// Giá trị hiển thị của một dòng (thư mục, file hoặc dòng tóm tắt).
@MainActor
struct RowInfo {
    let name: String
    let icon: NSImage
    let iconTint: NSColor?
    let note: String?
    let isRoot: Bool
    let sizeText: String
    let percent: Double
    let filesText: String
    let foldersText: String
    let modifiedText: String
    /// So sánh với lần quét đã lưu: thư mục mới, thay đổi dung lượng (+ tăng, - giảm)
    var isNew = false
    var changeText = ""
    var changeSign = 0
    var changeTip: String?

    init(item: AnyObject, model: AppModel) {
        if let d = item as? DirNode {
            if let change = model.comparisonChange(d) {
                isNew = model.comparisonIsNew(d)
                changeText = change == 0 && !isNew ? "" : (change < 0 ? "-" : "+") + FileOps.formatSize(abs(change))
                changeSign = change > 0 ? 1 : change < 0 ? -1 : 0
                changeTip = model.changeTip(d)
            }
            name = d.name
            isRoot = d.parent == nil
            let denied = d.isAccessDenied
            icon = denied ? Icons.lockedFolder : d.isMount ? Icons.volume : Icons.folder(named: d.name, path: { d.fullPath })
            iconTint = nil
            note = denied ? Loc.t("NoteDenied") : d.isMount ? Loc.t("NoteMount") : nil
            let size = d.size
            sizeText = FileOps.formatSize(size)
            let parentSize = d.parent?.size ?? size
            percent = parentSize > 0 ? min(100, max(0, Double(size) * 100 / Double(parentSize))) : 0
            filesText = FileOps.formatCount(d.fileCount)
            foldersText = FileOps.formatCount(d.dirCount)
            modifiedText = FileOps.formatDate(d.modified)
        } else {
            let f = item as! FileRow
            isRoot = false
            name = f.displayName
            icon = f.kind == .summary ? Icons.summary : Icons.file(named: f.name)
            iconTint = f.kind == .summary ? .secondaryLabelColor : nil
            note = nil
            sizeText = FileOps.formatSize(f.size)
            let parentSize = f.owner.size
            percent = parentSize > 0 ? min(100, max(0, Double(f.size) * 100 / Double(parentSize))) : 0
            filesText = f.kind == .summary ? FileOps.formatCount(f.count) : ""
            foldersText = ""
            modifiedText = f.kind == .summary ? "" : FileOps.formatDate(f.modified)
        }
    }
}

// ================= Ô hiển thị =================

final class NameCell: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let noteLabel = NSTextField(labelWithString: "")
    /// Nhãn "mới": thư mục chưa có trong lần quét đang so sánh
    private let badge = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = Theme.accentNS
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 3
        badge.layer?.backgroundColor = Theme.accentNS.withAlphaComponent(0.14).cgColor
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        icon.imageScaling = .scaleProportionallyDown
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        noteLabel.lineBreakMode = .byTruncatingTail
        imageView = icon
        textField = label

        let stack = NSStackView(views: [icon, label, badge, noteLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @MainActor
    func configure(_ info: RowInfo) {
        icon.image = info.icon
        icon.contentTintColor = info.iconTint
        label.stringValue = info.name
        label.font = info.isRoot ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
        noteLabel.stringValue = info.note ?? ""
        noteLabel.isHidden = info.note == nil
        badge.stringValue = info.isNew ? " " + Loc.t("CompareNew") + " " : ""
        badge.isHidden = !info.isNew
    }
}

final class TextCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        textField = label
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ text: String, alignment: NSTextAlignment, bold: Bool = false, color: NSColor? = nil) {
        label.stringValue = text
        label.alignment = alignment
        label.font = bold ? .monospacedDigitSystemFont(ofSize: 13, weight: .semibold) : .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = color ?? (bold ? .labelColor : .secondaryLabelColor)
        toolTip = nil
    }
}

final class PercentCell: NSTableCellView {
    private let bar = BarView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        label.textColor = .secondaryLabelColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        addSubview(label)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            bar.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.55),
            bar.heightAnchor.constraint(equalToConstant: 7),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(percent: Double, color: NSColor) {
        bar.fraction = percent / 100
        bar.color = color
        label.stringValue = String(format: "%.1f %%", percent)
    }
}

/// Thanh tiến trình mảnh bo tròn.
final class BarView: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var color: NSColor = Theme.accentNS { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let radius = r.height / 2
        Theme.trackNS.setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        let w = r.width * min(1, max(0, fraction))
        guard w > 0.5 else { return }
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: max(w, r.height), height: r.height),
                     xRadius: radius, yRadius: radius).fill()
    }
}
