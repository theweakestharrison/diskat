import SwiftUI
import DiskatCore

/// Nội dung menu "Thêm" (⋯), dùng cả trên thanh công cụ lẫn thanh menu.
struct MoreMenuItems: View {
    let model: AppModel

    var body: some View {
        CompareMenu(model: model)
        Divider()
        ExportMenuItems(model: model)
        Divider()
        Button(Loc.t("MenuCheckUpdates")) { Task { await model.checkForUpdates(userInitiated: true) } }
            .disabled(model.checkingUpdates)
        Toggle(Loc.t("MenuAutoUpdate"), isOn: Binding(get: { model.autoCheckUpdates }, set: { model.autoCheckUpdates = $0 }))
        Divider()
        ThemePicker(model: model)
        Divider()
        Button(Loc.t("MenuAbout")) { model.showAbout() }
    }
}

struct ExportMenuItems: View {
    let model: AppModel

    var body: some View {
        Button(Loc.t("MenuExportPdf")) { Task { await model.exportPdf() } }
            .disabled(!model.canExport)
        Button(Loc.t("MenuExportFolders")) { Task { await model.exportFoldersCsv() } }
            .disabled(!model.canExport)
        Button(Loc.t("MenuExportFiles")) { Task { await model.exportFilesCsv(model.displayedFiles) } }
            .disabled(!model.canExport || model.displayedFiles.isEmpty)
    }
}

/// Giao diện: theo hệ thống, sáng hoặc tối (đổi ngay, lưu lại).
struct ThemePicker: View {
    let model: AppModel

    var body: some View {
        Picker(Loc.t("MenuTheme"), selection: Binding(get: { model.theme }, set: { model.setTheme($0) })) {
            Text(Loc.t("ThemeSystem")).tag(AppTheme.system)
            Text(Loc.t("ThemeLight")).tag(AppTheme.light)
            Text(Loc.t("ThemeDark")).tag(AppTheme.dark)
        }
    }
}

/// "So sánh với lần quét trước": các lần quét đã lưu của thư mục đang xem, mới nhất trước.
struct CompareMenu: View {
    let model: AppModel

    var body: some View {
        Menu(Loc.t("MenuCompare")) {
            ForEach(model.savedScans, id: \.filePath) { s in
                Toggle("\(FileOps.formatDate(s.scannedAt.timeIntervalSince1970))  ·  \(FileOps.formatSize(s.totalSize))",
                       isOn: Binding(get: { model.isComparing && model.comparison?.info.filePath == s.filePath },
                                     set: { on in Task { if on { await model.startComparison(s) } else { model.stopComparison() } } }))
            }
            if model.savedScans.isEmpty {
                Button(Loc.t("MenuCompareNone")) {}.disabled(true)
            }
            if model.isComparing {
                Divider()
                Button(Loc.t("CompareStop")) { model.stopComparison() }
            }
            Divider()
            Toggle(Loc.t("MenuCompareSave"), isOn: Binding(get: { model.saveScanHistory }, set: { model.saveScanHistory = $0 }))
            Button(Loc.t("MenuCompareClear")) { Task { await model.deleteSavedScans() } }
                .disabled(model.savedScanCount == 0)
        }
        .disabled(model.root == nil || model.isBusy || model.isScanning)
    }
}
