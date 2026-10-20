import SwiftUI
import DiskatCore

struct MainView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var pathFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            DrivesBar()
            Divider()
            SplitPanes(left: TreePane(), right: RightPane(), leftMin: 480, rightMin: 340)
            Divider()
            StatusBar()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(Loc.t("WindowTitle"))
        .navigationSubtitle(Loc.t("AppSubtitle"))
        .toolbar { toolbar }
        .overlay {
            if let text = model.busyText { BusyOverlay(text: text) }
        }
        .sheet(item: $model.confirm) { ConfirmSheet(request: $0) }
        .dropDestination(for: URL.self) { urls, _ in
            guard let dir = urls.first(where: { FileOps.isDirectory($0.path) }) else { return false }
            model.startScan(dir.path)
            return true
        }
        // Thả thư mục lên biểu tượng Dock / "Mở bằng Diskat" trong Finder / Diskat.app/Contents/MacOS/Diskat <thư mục>.
        // Dùng onOpenURL (không dùng application(_:open:) của AppDelegate) để SwiftUI vẫn mở cửa sổ chính.
        .onOpenURL { url in
            if url.isFileURL, FileOps.isDirectory(url.path) { model.startScan(url.path) }
        }
        .onChange(of: pathFocused) { model.pathFieldFocused = pathFocused }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            @Bindable var model = model
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Theme.accent)
                TextField(Loc.t("PathPlaceholder"), text: $model.pathText)
                    .textFieldStyle(.plain)
                    .focused($pathFocused)
                    .onSubmit { model.scanFromField() }
            }
            .padding(.horizontal, 9)
            .frame(minWidth: 240, idealWidth: 460, maxWidth: 560, minHeight: 26)
            .modifier(PathFieldChrome())
            .help(Loc.t("PathTip"))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.browse() } label: {
                Label(Loc.t("Browse"), systemImage: "folder.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .help(Loc.t("BrowseTip"))

            if model.isScanning {
                Button { model.stopScan() } label: {
                    Label(Loc.t("Stop"), systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Theme.danger)
                }
            } else {
                Button { model.scanFromField() } label: {
                    Label(Loc.t("Scan"), systemImage: "magnifyingglass")
                        .labelStyle(.titleAndIcon)
                }
                .help(Loc.t("PathTip"))
            }

            if !model.hasFullDiskAccess {
                Button { model.requestFullDiskAccess() } label: {
                    Label(Loc.t("FullDiskAccess"), systemImage: "lock.shield")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Theme.amber)
                }
                .help(Loc.t("FullDiskAccessTip"))
            }

            Menu {
                ForEach(Loc.languages, id: \.code) { lang in
                    Toggle(lang.name, isOn: Binding(get: { Loc.lang == lang.code },
                                                    set: { if $0 { model.setLanguage(lang.code) } }))
                }
            } label: {
                Label(Loc.lang.uppercased(), systemImage: "globe")
                    .labelStyle(.titleAndIcon)
            }
            .help(Loc.t("LangTip"))

            // Menu "Thêm": so sánh lần quét, xuất báo cáo, cập nhật, giao diện, giới thiệu
            Menu {
                MoreMenuItems(model: model)
            } label: {
                Label(Loc.t("MenuMore"), systemImage: "ellipsis.circle")
            }
            .help(Loc.t("MenuMore"))
        }
    }
}

/// macOS 26 tự bọc mục trên thanh công cụ bằng lớp "kính"; bản cũ hơn cần viền như ô nhập liệu.
private struct PathFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}

/// Hai khung cạnh nhau với thanh chia kéo được; tỉ lệ được nhớ giữa các lần mở (mặc định giống bản Windows 1.25 : 1).
struct SplitPanes<Left: View, Right: View>: View {
    let left: Left
    let right: Right
    let leftMin: CGFloat
    let rightMin: CGFloat
    @AppStorage("splitFraction") private var fraction = 0.56
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let leftWidth = clamp(total * fraction, total)
            HStack(spacing: 0) {
                left.frame(width: leftWidth)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .overlay {
                        Color.clear
                            .frame(width: 9)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { g in
                                    let start = dragStart ?? leftWidth
                                    if dragStart == nil { dragStart = start }
                                    fraction = clamp(start + g.translation.width, total) / max(total, 1)
                                }
                                .onEnded { _ in dragStart = nil })
                    }
                right.frame(maxWidth: .infinity)
            }
        }
    }

    private func clamp(_ width: CGFloat, _ total: CGFloat) -> CGFloat {
        min(max(width, leftMin), max(leftMin, total - rightMin - 1))
    }
}

// ================= Ổ đĩa =================

struct DrivesBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.volumes) { DriveCard(volume: $0) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

struct DriveCard: View {
    @Environment(AppModel.self) private var model
    let volume: VolumeInfo
    @State private var hovering = false

    private var symbol: String {
        switch volume.kind {
        case .internal: "internaldrive"
        case .external: "externaldrive"
        case .network: "server.rack"
        }
    }

    private var kindText: String {
        switch volume.kind {
        case .internal: Loc.t("DriveInternal")
        case .external: Loc.t("DriveExternal")
        case .network: Loc.t("DriveNetwork")
        }
    }

    var body: some View {
        Button { model.startScan(volume.path) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(volume.name).fontWeight(.semibold).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(Int(volume.usedPercent.rounded()))%")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    SlimBar(fraction: volume.usedPercent / 100, color: Theme.driveColor(percent: volume.usedPercent))
                        .frame(height: 5)
                    Text(Loc.f("DriveFree", FileOps.formatSize(volume.available), FileOps.formatSize(volume.total)))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(width: 230)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(hovering ? Theme.accent.opacity(0.7) : Color(nsColor: .separatorColor)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Loc.f("DriveTip", "\(volume.name), \(kindText)", volume.format.isEmpty ? volume.path : volume.format,
                    FileOps.formatSize(volume.used), FileOps.formatSize(volume.available)))
    }
}

struct SlimBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color)
                    .frame(width: max(geo.size.height, geo.size.width * min(1, max(0, fraction))))
                    .opacity(fraction > 0.001 ? 1 : 0)
            }
        }
    }
}

// ================= Cây thư mục =================

struct TreePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("TreeTitle")).font(.headline)
                    Text(model.selectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(Loc.t("Collapse")) { model.collapseAll() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(model.root == nil)
                    .help(Loc.t("CollapseTip"))
                Button { model.revealSelected() } label: {
                    Label(Loc.t("Open"), systemImage: "folder")
                }
                .disabled(!model.hasSelection)
                .help(Loc.t("OpenTip"))
                Button { Task { await model.deleteSelected(permanent: false) } } label: {
                    Label(Loc.t("Delete"), systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.danger)
                .disabled(!model.canDeleteSelection)
                .help(Loc.t("DeleteTip"))
                Button { Task { await model.deleteSelected(permanent: true) } } label: {
                    Text(Loc.t("DeletePerm")).foregroundStyle(model.canDeleteSelection ? Theme.danger : Color.secondary)
                }
                .disabled(!model.canDeleteSelection)
                .help(Loc.t("DeletePermTip"))
            }
            .padding(.horizontal, 12)
            .frame(height: 50)

            if let summary = model.compareSummary {
                CompareBar(summary: summary, stopped: model.scanStopped) { model.stopComparison() }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            Divider()

            ZStack {
                FolderTree(model: model)
                if model.root == nil {
                    EmptyState().allowsHitTesting(false)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// Đang so sánh với một lần quét đã lưu: tóm tắt thay đổi và nút tắt.
struct CompareBar: View {
    let summary: String
    let stopped: Bool
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary).fontWeight(.semibold).lineLimit(1).truncationMode(.tail).help(summary)
                if stopped {
                    Text(Loc.t("CompareStopped")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button(Loc.t("CompareStop"), action: stop)
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.12)))
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            LogoView().frame(width: 76, height: 76).opacity(0.9)
            Text(Loc.t("EmptyTitle"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Text(Loc.t("EmptySub"))
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text(Loc.t("EmptyDrop"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// Logo vẽ từ hình vector dùng chung với biểu tượng ứng dụng.
struct LogoView: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.withCGContext { cg in
                LogoArt.draw(in: cg, rect: CGRect(origin: .zero, size: size), flipped: true)
            }
        }
    }
}

// ================= Bên phải: bản đồ, file lớn nhất, loại file, tuổi file, trùng lặp =================

extension RightTab {
    var titleKey: String {
        switch self {
        case .map: "TabMap"
        case .largest: "TabTopFiles"
        case .types: "TabTypes"
        case .ages: "TabAges"
        case .duplicates: "TabDuplicates"
        }
    }
}

struct RightPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // Khung hẹp (hoặc ngôn ngữ có nhãn dài): thanh phân đoạn không vừa thì chuyển thành menu
            ViewThatFits(in: .horizontal) {
                HStack {
                    tabPicker(segmented: true)
                    Spacer(minLength: 0)
                }
                HStack {
                    tabPicker(segmented: false)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 50)

            Divider()

            switch model.rightTab {
            case .map: MapPane()
            case .largest: LargestFilesPane()
            case .types: TypesPane()
            case .ages: AgesPane()
            case .duplicates: DuplicatesPane()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func tabPicker(segmented: Bool) -> some View {
        @Bindable var model = model
        let picker = Picker("", selection: $model.rightTab) {
            ForEach(RightTab.allCases, id: \.self) { Text(Loc.t($0.titleKey)).tag($0) }
        }
        .labelsHidden()
        if segmented {
            picker.pickerStyle(.segmented).fixedSize()
        } else {
            picker.pickerStyle(.menu).fixedSize()
        }
    }
}

struct MapPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { model.mapUp() } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(!model.canMapUp)
                .help(Loc.t("MapUpTip"))
                Text(model.mapRoot?.fullPath ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(mapSize)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
            }
            TreemapCanvas(model: model)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(model.mapHoverText ?? Loc.t("MapHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
    }

    private var mapSize: String {
        _ = model.valuesRevision
        return model.mapRoot.map { FileOps.formatSize($0.size) } ?? ""
    }
}

// ================= Thanh trạng thái / lớp phủ =================

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            if model.isScanning || model.isRescanning {
                ProgressView().controlSize(.small)
            }
            Text(model.status())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(model.statsText)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 30)
    }
}

struct BusyOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
            VStack(spacing: 14) {
                Text(text).font(.headline)
                ProgressView().progressViewStyle(.linear).frame(width: 240)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
            .shadow(radius: 12, y: 3)
        }
        .ignoresSafeArea()
    }
}
