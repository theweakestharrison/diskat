import SwiftUI
import DiskatCore

/// Một dòng trong tab Loại file / Tuổi file.
struct StatRow: Identifiable, Hashable {
    let id: String
    let label: String
    let ext: String
    let index: Int
    let size: Int64
    let count: Int64
    let percent: Double
    let color: Color
}

private func hex(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

// Giống bảng màu bản đồ; loại thứ 13 trở đi màu xám
private let typeColors: [Color] = [0x4F8DF5, 0x2FB59C, 0x6CB84A, 0xF2B12E, 0xF07F3C, 0xE5565B,
                                   0xD95CA8, 0x9B6CE0, 0x5C6BD8, 0x2EA8D6, 0xA3B835, 0xB07A52].map(hex)
private let otherTypes = hex(0x8E9AAF)
// Mới (xanh) đến cũ (cam đất), giống báo cáo PDF
let ageColors: [Color] = [0x2F6FED, 0x2EA8D6, 0x2FB59C, 0xA3B835, 0xF2B12E, 0xF07F3C].map(hex)

/// Bảng thống kê dùng chung cho hai tab.
private struct StatTable: View {
    let rows: [StatRow]
    let firstColumn: String
    let boldLabel: Bool
    let menuTitle: String
    let action: (StatRow) -> Void
    @State private var selection: Set<String> = []

    var body: some View {
        if #available(macOS 13, *) {
            ModernStatTable(rows: rows, firstColumn: firstColumn, boldLabel: boldLabel, menuTitle: menuTitle, action: action)
        } else { compatibleBody }
    }

    private var compatibleBody: some View {
        AppKitTable(rows: rows.map { AppKitTableRow(id: $0.id, cells: [$0.label, String(format: "%.1f %%", $0.percent), FileOps.formatSize($0.size), FileOps.formatCount($0.count)]) },
                    columns: [firstColumn, Loc.t("ColShare"), Loc.t("ColSize"), Loc.t("ColFiles")], selection: $selection,
                    onOpen: { ids in if let row = rows.first(where: { ids.contains($0.id) }) { action(row) } },
                    menu: { ids in
                        guard let row = rows.first(where: { ids.contains($0.id) }) else { return [] }
                        return [AppKitTableAction(title: menuTitle, action: { action(row) })]
                    })
    }
}

@available(macOS 13, *)
private struct ModernStatTable: View {
    let rows: [StatRow]
    let firstColumn: String
    let boldLabel: Bool
    let menuTitle: String
    let action: (StatRow) -> Void
    @State private var selection: String?

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn(firstColumn) { (r: StatRow) in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(r.color).frame(width: 10, height: 10)
                    Text(r.label).fontWeight(boldLabel ? .semibold : .regular).lineLimit(1)
                }
            }
            .width(min: 90, ideal: 150)
            TableColumn(Loc.t("ColShare")) { (r: StatRow) in
                HStack(spacing: 8) {
                    SlimBar(fraction: r.percent / 100, color: r.color).frame(width: 78, height: 7)
                    Text(String(format: "%.1f %%", r.percent)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .width(min: 120, ideal: 150)
            TableColumn(Loc.t("ColSize")) { (r: StatRow) in
                Text(FileOps.formatSize(r.size)).fontWeight(.semibold).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 64, ideal: 88)
            TableColumn(Loc.t("ColFiles")) { (r: StatRow) in
                Text(FileOps.formatCount(r.count)).foregroundStyle(.secondary).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 90)
        }
        .contextMenu(forSelectionType: String.self) { (ids: Set<String>) in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                Button(menuTitle) { action(row) }
            }
        } primaryAction: { (ids: Set<String>) in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }) { action(row) }
        }
    }
}

/// Tab Loại file: tổng theo phần mở rộng trong lần quét. Nhấp đúp để liệt kê mọi file của loại đó.
struct TypesPane: View {
    @EnvironmentObject private var model: AppModel

    private var rows: [StatRow] {
        let total = model.fileTypes.reduce(Int64(0)) { $0 + $1.size }
        return model.fileTypes.enumerated().map { i, t in
            StatRow(id: t.ext.isEmpty ? "\u{0}" : t.ext, label: t.ext.isEmpty ? Loc.t("PdfNoExt") : t.ext, ext: t.ext, index: i,
                    size: t.size, count: t.count, percent: total > 0 ? Double(t.size) * 100 / Double(total) : 0,
                    color: i < typeColors.count ? typeColors[i] : otherTypes)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.typesNote)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            StatTable(rows: rows, firstColumn: Loc.t("ColType"), boldLabel: true, menuTitle: Loc.t("MenuFindType")) { row in
                if !row.ext.isEmpty { model.findType(row.ext) }
            }
        }
    }
}

/// Tab Tuổi file: dung lượng theo lần sửa cuối. Nhấp đúp để tìm file cũ hơn mốc đó.
struct AgesPane: View {
    @EnvironmentObject private var model: AppModel

    private var rows: [StatRow] {
        let total = model.ageStats.reduce(Int64(0)) { $0 + $1.size }
        return model.ageStats.enumerated().map { i, a in
            StatRow(id: "age\(i)", label: Loc.t("Age\(i)"), ext: "", index: i, size: a.size, count: a.count,
                    percent: total > 0 ? Double(a.size) * 100 / Double(total) : 0, color: ageColors[i % ageColors.count])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.agesNote)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 8)
            // Thanh xếp chồng: tỷ lệ từng nhóm tuổi
            let rows = rows
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(rows.filter { $0.size > 0 }) { (r: StatRow) in
                        Rectangle().fill(r.color)
                            .frame(width: geo.size.width * r.percent / 100)
                            .help("\(r.label): \(FileOps.formatSize(r.size))")
                    }
                }
            }
            .frame(height: 14)
            .background(Theme.track)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            StatTable(rows: rows, firstColumn: Loc.t("ColModified"), boldLabel: false, menuTitle: Loc.t("MenuFindOlder")) { row in
                model.findOlder(bucket: row.index)
            }
        }
    }
}
