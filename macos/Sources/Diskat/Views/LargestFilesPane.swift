import SwiftUI
import DiskatCore

/// Tab "File lớn nhất": 500 file lớn nhất của lần quét, hoặc kết quả tìm theo tên / dung lượng / tuổi
/// trong cả thư mục đã quét; chọn nhiều để xóa.
struct LargestFilesPane: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            FindBar()
            Table(model.displayedFiles, selection: $model.topSelection) {
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
            // Danh sách mới (kết quả tìm / quay lại file lớn nhất): dựng bảng mới thay vì để bảng tính chênh lệch
            // giữa hai danh sách khác hẳn nhau (và cuộn về đầu kết quả)
            .id(model.searchGeneration)
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
                if model.topFiles.isEmpty && model.searchResults == nil {
                    Text(Loc.t("TopFilesEmpty"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: focused) { if focused { model.setActivePane(.largest) } }
            .onChange(of: model.topSelection) { model.setActivePane(.largest) }
        }
    }

    /// Menu chuột phải trên một dòng chưa chọn: thao tác trên đúng các dòng đó.
    private func select(_ ids: Set<String>) {
        if !ids.isSubset(of: model.topSelection) || ids.count != model.topSelection.count {
            model.topSelection = ids
        }
        model.setActivePane(.largest)
    }
}

/// Tìm file theo tên / dung lượng / tuổi trong toàn bộ thư mục đã quét.
private struct FindBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(Loc.t("FindNameHint"), text: $model.findText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.runFind() } }
                    .help(Loc.t("FindNameTip"))
                    .frame(minWidth: 110)
                Picker("", selection: $model.findSizeIndex) {
                    ForEach(AppModel.findSizeLabels.indices, id: \.self) { i in
                        Text(i == 0 ? Loc.t("FindSizeAny") : Loc.f("FindSizeMin", AppModel.findSizeLabels[i])).tag(i)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Picker("", selection: $model.findAgeIndex) {
                    ForEach(AppModel.findAgeDays.indices, id: \.self) { i in
                        Text(Loc.t("FindAge\(i)")).tag(i)
                    }
                }
                .labelsHidden()
                .fixedSize()
                if model.findProgress != nil {
                    Button(Loc.t("FindStop")) { model.cancelFind() }
                } else {
                    Button(Loc.t("FindSearch")) { Task { await model.runFind() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.root == nil)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                if model.findProgress != nil { ProgressView().controlSize(.mini) }
                Text(model.findInfoText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if model.searchResults != nil {
                    Button(Loc.t("FindClear")) { model.clearSearch() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
