import AppKit
import DiskatCore

/// Hộp thông báo dạng sheet gắn vào cửa sổ chính.
@MainActor
enum Dialogs {
    @discardableResult
    static func alert(_ message: String, detail: String = "", style: NSAlert.Style = .informational,
                      buttons: [String] = []) async -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = style
        for title in buttons.isEmpty ? [Loc.t("OK")] : buttons { alert.addButton(withTitle: title) }
        if buttons.count > 1 { alert.buttons.last?.keyEquivalent = "\u{1b}" }

        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.attachedSheet == nil }) else {
            return alert.runModal()
        }
        return await withCheckedContinuation { cont in
            alert.beginSheetModal(for: window) { cont.resume(returning: $0) }
        }
    }
}

/// Menu chuột phải dùng chung cho cây thư mục và bản đồ (thao tác trên dòng đang chọn trong cây).
@MainActor
enum ContextMenus {
    final class Item: NSMenuItem {
        private let handler: () -> Void

        init(_ title: String, symbol: String? = nil, key: String = "", modifiers: NSEvent.ModifierFlags = [],
             enabled: Bool = true, danger: Bool = false, handler: @escaping () -> Void) {
            self.handler = handler
            super.init(title: title, action: #selector(fire), keyEquivalent: key)
            target = self
            keyEquivalentModifierMask = modifiers
            isEnabled = enabled
            if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            if danger {
                attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: Theme.dangerNS])
            }
        }

        required init(coder: NSCoder) { fatalError() }

        @objc private func fire() { handler() }
    }

    static func tree(_ model: AppModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let has = model.hasSelection
        let target = model.rescanTarget
        let delete = "\u{8}" // ⌫
        menu.addItem(Item(Loc.t("MenuReveal"), symbol: "folder", enabled: has) { model.revealSelected() })
        menu.addItem(Item(Loc.t("MenuOpen"), enabled: has) { model.openSelected() })
        menu.addItem(Item(Loc.t("MenuCopy"), symbol: "doc.on.doc", key: "c", modifiers: [.command, .option], enabled: has) {
            model.copySelectedPath()
        })
        menu.addItem(.separator())
        menu.addItem(Item(Loc.t("MenuMap"), symbol: "square.grid.2x2", enabled: target != nil) { model.showSelectedOnMap() })
        menu.addItem(Item(Loc.t("MenuRescan"), symbol: "arrow.clockwise", key: "r", modifiers: .command,
                          enabled: target != nil && !model.isBusy && !model.isScanning) { model.rescanSelected() })
        menu.addItem(.separator())
        menu.addItem(Item(Loc.t("MenuTrash"), symbol: "trash", key: delete, modifiers: .command,
                          enabled: model.canDeleteSelection) { Task { await model.deleteSelected(permanent: false) } })
        menu.addItem(Item(Loc.t("MenuDeletePerm"), key: delete, modifiers: [.command, .option],
                          enabled: model.canDeleteSelection, danger: true) { Task { await model.deleteSelected(permanent: true) } })
        return menu
    }
}
