import SwiftUI
import DiskatCore

/// Tab "File lớn nhất": 500 file lớn nhất của lần quét, chọn nhiều để xóa.
struct LargestFilesPane: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        Table(model.topFiles, selection: $model.topSelection) {
            TableColumn(Loc.t("ColFileName")) { f in
                HStack(spacing: 6) {
                    Image(nsImage: Icons.file(named: f.name))
                    Text(f.name).lineLimit(1).truncationMode(.middle)
                }
                .help(f.path)
            }
            .width(min: 120, ideal: 200)
            TableColumn(Loc.t("ColSize")) { f in
                Text(FileOps.formatSize(f.size))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 64, ideal: 76, max: 110)
            TableColumn(Loc.t("ColFolder")) { f in
                Text(f.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 100, ideal: 220)
            TableColumn(Loc.t("ColModified")) { f in
                Text(FileOps.formatDate(f.modified)).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 80, ideal: 112)
        }
        .focused($focused)
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                Button(Loc.t("MenuReveal")) { select(ids); model.revealTopFile() }
                Button(Loc.t("MenuOpen")) { select(ids); model.openTopFile() }
                Button(Loc.t("MenuCopy")) { select(ids); model.copyTopFiles() }
                Divider()
                Button(Loc.t("MenuTrash")) { select(ids); Task { await model.deleteTopFiles(permanent: false) } }
                    .disabled(model.isBusy || model.isScanning)
                Button(Loc.t("MenuDeletePerm"), role: .destructive) { select(ids); Task { await model.deleteTopFiles(permanent: true) } }
                    .disabled(model.isBusy || model.isScanning)
            }
        } primaryAction: { ids in
            if let id = ids.first { Finder.reveal(id) }
        }
        .overlay {
            if model.topFiles.isEmpty {
                Text(Loc.t("TopFilesEmpty"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: focused) { if focused { model.activePane = .largest } }
        .onChange(of: model.topSelection) { model.activePane = .largest }
    }

    /// Menu chuột phải trên một dòng chưa chọn: thao tác trên đúng các dòng đó.
    private func select(_ ids: Set<String>) {
        if !ids.isSubset(of: model.topSelection) || ids.count != model.topSelection.count {
            model.topSelection = ids
        }
        model.activePane = .largest
    }
}
