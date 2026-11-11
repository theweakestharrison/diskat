import AppKit
import SwiftUI

struct AppKitTableRow {
    let id: String
    let cells: [String]
    var views: [AnyView]? = nil
}
struct AppKitTableAction {
    let title: String
    var enabled = true
    let action: () -> Void
}
struct AppKitTable: NSViewRepresentable {
    let rows: [AppKitTableRow]
    let columns: [String]
    @Binding var selection: Set<String>
    var onSelection: () -> Void = {}
    var onOpen: (Set<String>) -> Void = { _ in }
    var menu: (Set<String>) -> [AppKitTableAction] = { _ in [] }
    var onSpace: (() -> Void)? = nil
    var rowHeight: CGFloat = 22
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = MenuTable()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.allowsMultipleSelection = true
        table.rowHeight = rowHeight
        table.onFocus = onSelection
        table.onSpace = onSpace
        table.onReturn = { [weak coordinator = context.coordinator] in coordinator?.open() }
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.open)
        table.menuProvider = { [weak coordinator = context.coordinator] event in coordinator?.contextMenu(event) }
        for (i, title) in columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(i)))
            column.title = title
            column.minWidth = 65
            column.width = i == 0 || i == 2 ? 220 : 115
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let table = c.table else { return }
        c.updating = true
        for (i, column) in table.tableColumns.enumerated() { column.title = columns[i] }
        table.onFocus = onSelection
        table.onSpace = onSpace
        let ids = rows.map(\.id)
        let cells = rows.map(\.cells)
        if c.renderedIDs != ids || c.renderedCells != cells {
            table.reloadData()
            c.renderedIDs = ids
            c.renderedCells = cells
        }
        table.selectRowIndexes(IndexSet(rows.indices.filter { selection.contains(rows[$0].id) }), byExtendingSelection: false)
        c.updating = false
    }
    final class MenuTable: NSTableView {
        var menuProvider: ((NSEvent) -> NSMenu?)?
        var onFocus: (() -> Void)?
        var onSpace: (() -> Void)?
        var onReturn: (() -> Void)?
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocus?() }
            return accepted
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 49, let onSpace = onSpace { onSpace(); return }
            if event.keyCode == 36 { onReturn?(); return }
            super.keyDown(with: event)
        }
        override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(event) }
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: AppKitTable
        weak var table: MenuTable?
        var renderedIDs: [String] = []
        var renderedCells: [[String]] = []
        var updating = false
        var actions: [AppKitTableAction] = []
        init(_ parent: AppKitTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }
        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard let i = column.flatMap({ Int($0.identifier.rawValue) }), parent.rows.indices.contains(row) else { return nil }
            if let views = parent.rows[row].views, views.indices.contains(i) {
                return NSHostingView(rootView: views[i])
            }
            let field = NSTextField(labelWithString: parent.rows[row].cells[i])
            field.lineBreakMode = .byTruncatingMiddle
            field.toolTip = parent.rows[row].cells.joined(separator: "\n")
            return field
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = table else { return }
            parent.selection = Set(table.selectedRowIndexes.compactMap { parent.rows.indices.contains($0) ? parent.rows[$0].id : nil })
            parent.onSelection()
        }
        @objc func open() { parent.onOpen(parent.selection) }
        func contextMenu(_ event: NSEvent) -> NSMenu? {
            guard let table = table else { return nil }
            let row = table.row(at: table.convert(event.locationInWindow, from: nil))
            guard parent.rows.indices.contains(row) else { return nil }
            if !table.selectedRowIndexes.contains(row) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            actions = parent.menu(parent.selection)
            let result = NSMenu()
            result.autoenablesItems = false
            for (i, action) in actions.enumerated() {
                let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i
                item.isEnabled = action.enabled
                result.addItem(item)
            }
            return result
        }
        @objc func runAction(_ item: NSMenuItem) { if actions.indices.contains(item.tag) { actions[item.tag].action() } }
    }
}
