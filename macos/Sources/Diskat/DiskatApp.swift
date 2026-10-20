import AppKit
import SwiftUI
import DiskatCore

@main
struct DiskatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    init() {
        // AppKit mặc định coi đường dẫn trên dòng lệnh là "mở tài liệu" và khi đó SwiftUI không mở cửa sổ chính.
        // Diskat tự đọc đối số trong AppModel.launched().
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
    }

    var body: some Scene {
        Window(Loc.t("WindowTitle"), id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 600)
        }
        .defaultSize(width: 1360, height: 840)
        .commands { DiskatCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cần khi chạy trực tiếp file thực thi (swift run) thay vì gói .app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        MainActor.assumeIsolated { AppModel.shared.launched() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.stopScan() }
    }
}

/// Thanh menu: phím tắt theo quy ước của Finder (⌘⌫ chuyển vào Thùng rác, ⌥⌘⌫ xóa ngay, ⌥⌘C sao chép đường dẫn).
struct DiskatCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(Loc.t("Browse")) { model.browse() }
                .keyboardShortcut("o")
            Divider()
            Button(Loc.t("MenuRescan")) { model.rescanSelected() }
                .keyboardShortcut("r")
                .disabled(model.rescanTarget == nil || model.isBusy || model.isScanning)
            Button(Loc.t("Stop")) { model.stopScan() }
                .keyboardShortcut(".")
                .disabled(!model.isScanning)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button(Loc.t("MenuCopy")) { model.copyActive() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model.pathFieldFocused)
            Button(Loc.t("MenuTrash")) { model.deleteActive(permanent: false) }
                .keyboardShortcut(.delete)
                .disabled(!model.canDeleteActive)
            Button(Loc.t("MenuDeletePerm")) { model.deleteActive(permanent: true) }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(!model.canDeleteActive)
        }
        CommandGroup(before: .toolbar) {
            Button(Loc.t("MenuReveal")) { model.revealActive() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(Loc.t("CollapseTip")) { model.collapseAll() }
                .disabled(model.root == nil)
            Divider()
            Button(Loc.t("TabMap")) { model.rightTab = .map }
                .keyboardShortcut("1")
            Button(Loc.t("TabTopFiles")) { model.rightTab = .largest }
                .keyboardShortcut("2")
            Button(Loc.t("MapUpTip")) { model.mapUp() }
                .keyboardShortcut(.upArrow)
                .disabled(!model.canMapUp || model.pathFieldFocused)
            Divider()
            Picker(Loc.t("LangTip"), selection: Binding(get: { Loc.lang }, set: { model.setLanguage($0) })) {
                ForEach(Loc.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
            if !model.hasFullDiskAccess {
                Button(Loc.t("FullDiskAccess") + "…") { model.requestFullDiskAccess() }
            }
            Divider()
        }
    }
}
