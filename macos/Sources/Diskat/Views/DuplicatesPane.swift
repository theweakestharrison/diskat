import SwiftUI
import DiskatCore

/// Tab Trùng lặp: tìm file giống hệt nhau trong thư mục đã quét, đánh dấu các bản thừa rồi xóa an toàn.
struct DuplicatesPane: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        let dup = model.duplicates
        @Bindable var bindable = dup
        VStack(alignment: .leading, spacing: 0) {
            // Dung lượng tối thiểu, bỏ qua thư mục hệ thống, nút Tìm / Dừng
            HStack(spacing: 10) {
                Picker("", selection: $bindable.minSizeIndex) {
                    ForEach(DuplicatesModel.sizeLabels.indices, id: \.self) { i in
                        Text(Loc.f("FindSizeMin", DuplicatesModel.sizeLabels[i])).tag(i)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help(Loc.t("DupMinTip"))
                Toggle(Loc.t("DupSkipSystem"), isOn: $bindable.skipSystem)
                    .toggleStyle(.checkbox)
                    .help(Loc.t("DupSkipSystemTip"))
                Spacer(minLength: 6)
                if dup.running {
                    Button(Loc.t("FindStop")) { dup.cancel() }
                } else {
                    Button(Loc.t("DupFind")) {
                        if let root = model.root, !model.isScanning { Task { await dup.run(root: root) } }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.root == nil || model.isScanning)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(dup.info(root: model.root, scanning: model.isScanning))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if dup.running {
                    if let fraction = dup.progressFraction {
                        ProgressView(value: fraction).controlSize(.small)
                    } else {
                        ProgressView().progressViewStyle(.linear).controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            List(selection: $bindable.selection) {
                ForEach(dup.groups ?? []) { g in
                    GroupHeader(group: g)
                        .tag("g:" + g.id.uuidString)
                    if g.isExpanded {
                        ForEach(g.files) { f in
                            FileLine(file: f).tag(f.path)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .focused($focused)
            .contextMenu(forSelectionType: String.self) { ids in
                if !ids.isEmpty {
                    Button(Loc.t("MenuReveal")) { select(ids); model.revealActive() }
                    Button(Loc.t("MenuOpen")) { select(ids); if let f = dup.selectedFiles.first { Finder.open(f.path) } }
                    Button(Loc.t("MenuCopy")) { select(ids); model.copyActive() }
                    Divider()
                    Button(Loc.t("DupDeletePerm"), role: .destructive) { Task { await model.deleteDuplicates(permanent: true) } }
                        .disabled(dup.checkedCount == 0 || model.isBusy)
                }
            } primaryAction: { ids in
                guard let id = ids.first else { return }
                if let f = dup.file(id) { Finder.reveal(f.path) }
                else if let g = dup.groups?.first(where: { "g:" + $0.id.uuidString == id }) { g.isExpanded.toggle() }
            }
            .onKeyPress(.space) {
                dup.toggleSelected()
                return .handled
            }
            .onChange(of: focused) { if focused { model.setActivePane(.duplicates) } }
            .onChange(of: dup.selection) { model.setActivePane(.duplicates) }
            .overlay {
                if dup.groups == nil && !dup.running {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }

            // Chọn nhanh và xóa các bản đã đánh dấu
            if let groups = dup.groups, !groups.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(dup.selectionInfo)
                        .font(.caption)
                        .foregroundStyle(dup.notice != nil ? Theme.danger : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Button(Loc.t("DupSelectButNewest")) { dup.selectAllButNewest() }
                            .help(Loc.t("DupSelectButNewestTip"))
                        Button(Loc.t("DupClearSelection")) { dup.clearChecks() }
                            .disabled(dup.checkedCount == 0)
                        Spacer(minLength: 6)
                        Button { Task { await model.deleteDuplicates(permanent: NSEvent.modifierFlags.contains(.option)) } } label: {
                            Label(Loc.t("DupDelete"), systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.danger)
                        .disabled(dup.checkedCount == 0 || model.isBusy || model.isScanning)
                        .help(Loc.t("DupDeleteTip"))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    private func select(_ ids: Set<String>) {
        let dup = model.duplicates
        if ids != dup.selection { dup.selection = ids }
        model.setActivePane(.duplicates)
    }
}

/// Tiêu đề nhóm: tên file, số bản, dung lượng lãng phí.
private struct GroupHeader: View {
    let group: DupGroupState

    var body: some View {
        HStack(spacing: 8) {
            Button { group.isExpanded.toggle() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(group.isExpanded ? 90 : 0))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Image(systemName: "doc.on.doc")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                Text(Loc.f("DupGroupCopies", FileOps.formatCount(group.files.count), FileOps.formatSize(group.size)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Loc.f("DupGroupWasted", FileOps.formatSize(group.wasted))).fontWeight(.semibold).monospacedDigit()
                let n = group.checkedCount
                if n > 0 {
                    Text(Loc.f("DupGroupSelected", FileOps.formatCount(n))).font(.caption).foregroundStyle(Theme.danger)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Một bản trong nhóm: ô đánh dấu để xóa, tên, thư mục, ngày sửa.
private struct FileLine: View {
    @Environment(AppModel.self) private var model
    let file: DupFileState

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { file.isChecked }, set: { model.duplicates.setChecked(file, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!file.canCheck)
            Image(nsImage: Icons.file(named: file.name))
            (Text(file.name).foregroundStyle(file.isChecked ? Theme.danger : .primary)
                + Text("   " + file.folder).font(.caption).foregroundStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if let note = file.note {
                Text(note).font(.caption).italic().foregroundStyle(.secondary)
            }
            Text(FileOps.formatDate(file.file.modified)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.leading, 22)
        .help(file.tip)
    }
}
