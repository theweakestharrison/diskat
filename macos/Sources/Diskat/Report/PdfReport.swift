import AppKit
import ImageIO
import UniformTypeIdentifiers
import DiskatCore

/// change / isNew: chỉ có khi đang so sánh với một lần quét đã lưu.
struct ReportFolder {
    let name: String
    let size: Int64
    let files: Int64
    let blocked: Bool
    let isOwnFiles: Bool
    var change: Int64? = nil
    var isNew = false
}

struct ReportFile {
    let name: String
    let folder: String
    let size: Int64
    let modified: Double
}

/// Ảnh chụp số liệu tại thời điểm xuất.
struct ReportData {
    let rootPath: String
    let scannedAt: Date
    let scanSeconds: Double
    let scanStopped: Bool
    let totalSize: Int64
    let files: Int64
    let folders: Int64
    let blocked: Int
    let statsStale: Bool
    let volumeName: String?
    let volumeTotal: Int64
    let volumeFree: Int64
    let treemap: CGImage?
    let topFolders: [ReportFolder]
    let topFiles: [ReportFile]
    let types: [TypeStat]
    let ages: [AgeStat]
    let version: String
    /// Tóm tắt thay đổi so với lần quét đang so sánh ("Tăng 3.2 GB so với lần quét lúc ..."), nil nếu không so sánh
    var compare: String? = nil
}

/// Báo cáo phân tích dung lượng dạng PDF (A4), dựng bằng Quartz (giống UI/PdfReport.cs của bản Windows).
/// Chữ vẽ bằng AppKit nên font dự phòng cho chữ Trung, Nhật, Hàn, Việt được hệ thống tự chọn.
@MainActor
enum PdfReport {
    static let pageW: CGFloat = 595.28, pageH: CGFloat = 841.89
    static let margin: CGFloat = 40, footerH: CGFloat = 28
    static var contentW: CGFloat { pageW - 2 * margin }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static let accent = rgb(0x2F6FED)
    static let accentSoft = rgb(0xE8F0FE)
    static let ink = rgb(0x1F2430)
    static let sub = rgb(0x6B7280)
    static let line = rgb(0xE3E7EE)
    static let card = rgb(0xF5F7FA)
    static let warn = rgb(0xFFF4DD)
    static let warnInk = rgb(0x8A5A00)
    static let growInk = rgb(0xB4380F)
    static let shrinkInk = rgb(0x146C36)
    // Màu nhóm tuổi file: mới (xanh) đến cũ (cam đất), giống tab Tuổi file
    static let ageColors: [NSColor] = [0x2F6FED, 0x2EA8D6, 0x2FB59C, 0xA3B835, 0xF2B12E, 0xF07F3C].map(rgb)

    static func write(_ data: ReportData, to path: String) throws {
        // Lượt 1 chỉ đo để biết tổng số trang ("Trang 1 / 3"), lượt 2 mới vẽ
        let dry = Writer(data, ctx: nil, totalPages: 0)
        dry.build()

        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: Loc.t("PdfTitle") + " - " + data.rootPath,
            kCGPDFContextCreator: "Diskat " + data.version,
            kCGPDFContextSubject: data.rootPath,
        ]
        guard let ctx = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: path])
        }
        let w = Writer(data, ctx: ctx, totalPages: dry.pageCount)
        w.build()
        w.endPage()
        ctx.closePDF()
    }

    /// Ảnh bản đồ cho báo cáo: luôn màu sáng, độ phân giải gấp đôi, nén JPEG (nhỏ hơn nhiều so với ảnh không nén).
    static func renderTreemap(root: DirNode, files: TreemapFiles?) -> CGImage? {
        let out = TreemapRenderer.render(root: root, files: files, size: CGSize(width: 760, height: 440), scale: 2,
                                         dark: false, background: CGColor(gray: 1, alpha: 1))
        guard let image = out.image else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return image }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest), let src = CGImageSourceCreateWithData(data, nil),
              let jpeg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return image }
        return jpeg
    }

    @MainActor
    private final class Writer {
        private let d: ReportData
        private let ctx: CGContext?
        private let totalPages: Int
        private(set) var pageCount = 0
        private var pageOpen = false
        private var y: CGFloat = 0

        init(_ d: ReportData, ctx: CGContext?, totalPages: Int) {
            self.d = d
            self.ctx = ctx
            self.totalPages = totalPages
        }

        private var drawing: Bool { ctx != nil }
        private var bottom: CGFloat { pageH - margin - footerH }

        // ---------------- Trang ----------------

        private func newPage() {
            endPage()
            pageCount += 1
            if let ctx {
                ctx.beginPDFPage(nil)
                // Trục y hướng xuống như trên màn hình
                ctx.translateBy(x: 0, y: pageH)
                ctx.scaleBy(x: 1, y: -1)
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            }
            pageOpen = true
            y = margin
            drawHeader()
        }

        func endPage() {
            guard pageOpen else { return }
            if let ctx {
                drawFooter()
                NSGraphicsContext.current = nil
                ctx.endPDFPage()
            }
            pageOpen = false
        }

        private func ensure(_ height: CGFloat) {
            if y + height > bottom { newPage() }
        }

        // ---------------- Chữ và hình ----------------

        private func attributed(_ s: String, _ size: CGFloat, _ color: NSColor, bold: Bool,
                                truncation: NSLineBreakMode = .byTruncatingTail) -> NSAttributedString {
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = truncation
            return NSAttributedString(string: s, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                .foregroundColor: color, .paragraphStyle: para,
            ])
        }

        /// Một dòng chữ; y là mép trên của dòng. Trả về độ rộng đã dùng.
        @discardableResult
        private func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor, bold: Bool = false,
                          maxWidth: CGFloat = 0, right: Bool = false, middle: Bool = false) -> CGFloat {
            let a = attributed(s, size, color, bold: bold, truncation: middle ? .byTruncatingMiddle : .byTruncatingTail)
            var w = ceil(a.size().width)
            if maxWidth > 0 { w = min(w, maxWidth) }
            if drawing {
                let left = right ? x - w : x
                a.draw(in: CGRect(x: left, y: y, width: w + 1, height: ceil(size * 1.4)))
            }
            return w
        }

        private func lineHeight(_ size: CGFloat) -> CGFloat { size * 1.45 }

        private func paragraphHeight(_ s: String, width: CGFloat, size: CGFloat) -> CGFloat {
            let a = attributed(s, size, ink, bold: false, truncation: .byWordWrapping)
            return ceil(a.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin]).height)
        }

        /// Đoạn văn có xuống dòng, trả về chiều cao đã dùng.
        @discardableResult
        private func paragraph(_ s: String, _ x: CGFloat, _ y: CGFloat, width: CGFloat, size: CGFloat, color: NSColor) -> CGFloat {
            let h = paragraphHeight(s, width: width, size: size)
            if drawing {
                attributed(s, size, color, bold: false, truncation: .byWordWrapping)
                    .draw(with: CGRect(x: x, y: y, width: width, height: h + 2), options: [.usesLineFragmentOrigin])
            }
            return h
        }

        private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, radius: CGFloat = 0) {
            guard drawing, w > 0, h > 0 else { return }
            color.setFill()
            if radius > 0 {
                NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
            } else {
                CGRect(x: x, y: y, width: w, height: h).fill()
            }
        }

        private func hline(_ y: CGFloat, _ color: NSColor, width: CGFloat = 0.75) {
            guard let ctx else { return }
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.move(to: CGPoint(x: margin, y: y))
            ctx.addLine(to: CGPoint(x: pageW - margin, y: y))
            ctx.strokePath()
        }

        private func upper(_ s: String) -> String { s.uppercased(with: Locale(identifier: Loc.lang)) }
        private func count(_ n: Int64) -> String { FileOps.formatCount(n) }
        private func size(_ n: Int64) -> String { FileOps.formatSize(n) }
        private func pct(_ p: Double) -> String { p >= 10 ? String(format: "%.0f%%", p) : String(format: "%.1f%%", p) }

        // ---------------- Nội dung ----------------

        func build() {
            newPage()
            summary()
            treemap()
            folders()
            files()
            types()
            ages()
            notes()
        }

        private func drawHeader() {
            var x = margin
            if let ctx {
                LogoArt.draw(in: ctx, rect: CGRect(x: x, y: y - 2, width: 18, height: 18), flipped: true)
            }
            x += 24
            text("Diskat", x, y, 11, ink, bold: true)
            text(Loc.t("PdfTitle"), pageW - margin, y + 1, 9, sub, right: true)
            y += 22
            hline(y, line)
            y += 18
        }

        private func drawFooter() {
            let fy = pageH - margin - 10
            hline(fy - 6, line)
            text("Diskat " + d.version + "  ·  diskat.cc", margin, fy, 8, sub)
            text(Loc.f("PdfPage", pageCount, totalPages), pageW - margin, fy, 8, sub, right: true)
        }

        private func summary() {
            let name = d.rootPath == "/" ? "/" : (d.rootPath as NSString).lastPathComponent
            text(name, margin, y, 22, ink, bold: true, maxWidth: contentW)
            y += 31
            text(d.rootPath, margin, y, 9.5, sub, maxWidth: contentW, middle: true)
            y += 15
            text(Loc.f("PdfScanned", FileOps.formatDate(d.scannedAt.timeIntervalSince1970), d.scanSeconds), margin, y, 9.5, sub,
                 maxWidth: contentW)
            if let compare = d.compare {
                y += 15
                text(compare, margin, y, 9.5, accent, bold: true, maxWidth: contentW)
            }
            y += 24

            var cards: [(label: String, value: String, note: String?)] = [
                (Loc.t("PdfTotal"), size(d.totalSize), nil),
                (Loc.t("PdfFiles"), count(d.files), nil),
                (Loc.t("PdfFolders"), count(d.folders), nil),
            ]
            if let v = d.volumeName, d.volumeTotal > 0 {
                cards.append((Loc.f("PdfFree", v), size(d.volumeFree), Loc.f("PdfFreeOf", size(d.volumeTotal))))
            }
            let gap: CGFloat = 10, h: CGFloat = 58
            let cw = (contentW - gap * CGFloat(cards.count - 1)) / CGFloat(cards.count)
            for (i, c) in cards.enumerated() {
                let x = margin + CGFloat(i) * (cw + gap)
                rect(x, y, cw, h, card, radius: 6)
                // Tên ổ trên Mac dài ("Macintosh HD"): nhãn dùng cả dòng, ghi chú (vd. "of 245 GB") nằm sau con số
                text(upper(c.label), x + 12, y + 10, 7.5, sub, bold: true, maxWidth: cw - 24)
                let vw = text(c.value, x + 12, y + 24, 17, ink, bold: true, maxWidth: cw - 24)
                if let note = c.note, vw + 40 < cw - 24 {
                    text(note, x + 12 + vw + 5, y + 32, 8, sub, maxWidth: cw - 29 - vw)
                }
            }
            y += h + 12

            // Cảnh báo số liệu thiếu
            var warnings: [String] = []
            if d.scanStopped { warnings.append(Loc.t("PdfStopped")) }
            if d.blocked > 0 { warnings.append(Loc.f("PdfIncomplete", count(Int64(d.blocked)))) }
            for w in warnings {
                let bh = paragraphHeight(w, width: contentW - 24, size: 9) + 16
                rect(margin, y, contentW, bh, warn, radius: 6)
                paragraph(w, margin + 12, y + 8, width: contentW - 24, size: 9, color: warnInk)
                y += bh + 8
            }
            y += 6
        }

        private func sectionTitle(_ title: String, needBelow: CGFloat) {
            ensure(30 + needBelow)
            text(title, margin, y, 13, ink, bold: true)
            y += 22
        }

        private func treemap() {
            guard let image = d.treemap else { return }
            let h = contentW * CGFloat(image.height) / CGFloat(max(1, image.width))
            sectionTitle(Loc.t("PdfMap"), needBelow: h)
            if drawing {
                NSImage(cgImage: image, size: NSSize(width: contentW, height: h))
                    .draw(in: CGRect(x: margin, y: y, width: contentW, height: h), from: .zero, operation: .sourceOver,
                          fraction: 1, respectFlipped: true, hints: nil)
            }
            y += h + 22
        }

        private struct Col {
            let text: String
            let x: CGFloat
            let w: CGFloat
            let right: Bool
        }

        private func tableHeader(_ cols: [Col]) {
            for c in cols {
                if c.right { text(upper(c.text), c.x + c.w, y, 7.5, sub, bold: true, right: true) }
                else { text(upper(c.text), c.x, y, 7.5, sub, bold: true, maxWidth: c.w) }
            }
            y += 13
            hline(y, line)
            y += 5
        }

        private func shareBar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ p: Double, _ color: NSColor) {
            rect(x, y, w, 5, accentSoft, radius: 2.5)
            rect(x, y, max(1.5, w * CGFloat(min(100, max(0, p))) / 100), 5, color, radius: 2.5)
        }

        private func folders() {
            guard !d.topFolders.isEmpty else { return }
            sectionTitle(Loc.t("PdfTopFolders"), needBelow: 18 * 3 + 18)
            // Đang so sánh với lần quét trước: thêm cột Thay đổi, thu hẹp cột tên và thanh tỉ lệ
            let cmp = d.compare != nil
            let nameW: CGFloat = cmp ? 190 : 262, barW: CGFloat = cmp ? 64 : 80
            let xNum = margin, xName = margin + 18, xBar = xName + nameW + 10, xPct = xBar + barW + 35, xSize = xPct + 60
            let xChange = xSize + 70, xFiles = pageW - margin
            func head() {
                var cols = [Col(text: "#", x: xNum, w: 16, right: false), Col(text: Loc.t("PdfColName"), x: xName, w: nameW, right: false),
                            Col(text: Loc.t("PdfColShare"), x: xBar, w: barW, right: false),
                            Col(text: Loc.t("PdfColSize"), x: xSize - 60, w: 60, right: true)]
                if cmp { cols.append(Col(text: Loc.t("ColChange"), x: xChange - 60, w: 60, right: true)) }
                cols.append(Col(text: Loc.t("PdfColFiles"), x: xFiles - 60, w: 60, right: true))
                tableHeader(cols)
            }
            head()
            for (i, f) in d.topFolders.enumerated() {
                if y + 18 > bottom { newPage(); head() }
                let p = d.totalSize > 0 ? Double(f.size) * 100 / Double(d.totalSize) : 0
                text("\(i + 1)", xNum, y, 9, sub)
                let label = f.isOwnFiles ? Loc.t("PdfOwnFiles") : f.name
                let nw = text(label, xName, y, 9.5, f.isOwnFiles ? sub : ink, bold: !f.isOwnFiles, maxWidth: nameW)
                if f.blocked {
                    text("  " + Loc.t("PdfBlocked"), xName + nw, y + 1, 8, warnInk, maxWidth: max(1, nameW - nw))
                } else if f.isNew {
                    text("  " + Loc.t("CompareNew"), xName + nw, y + 1, 8, accent, bold: true, maxWidth: max(1, nameW - nw))
                }
                shareBar(xBar, y + 4.5, barW, p, accent)
                text(pct(p), xPct, y, 8.5, sub, right: true)
                text(size(f.size), xSize, y, 9.5, ink, bold: true, right: true)
                if cmp, let ch = f.change, ch != 0 || f.isNew {
                    text((ch < 0 ? "-" : "+") + size(abs(ch)), xChange, y, 9, ch < 0 ? shrinkInk : growInk, bold: true, right: true)
                }
                text(count(f.files), xFiles, y, 9, sub, right: true)
                y += 18
            }
            y += 16
        }

        private func files() {
            guard !d.topFiles.isEmpty else { return }
            sectionTitle(Loc.t("PdfTopFiles"), needBelow: 18 * 3 + 18)
            let xName = margin, xFolder = margin + 190, xMod = margin + 390, xSize = pageW - margin
            func head() {
                tableHeader([Col(text: Loc.t("PdfColName"), x: xName, w: 180, right: false),
                             Col(text: Loc.t("PdfColFolder"), x: xFolder, w: 190, right: false),
                             Col(text: Loc.t("PdfColModified"), x: xMod, w: 80, right: false),
                             Col(text: Loc.t("PdfColSize"), x: xSize - 60, w: 60, right: true)])
            }
            head()
            for f in d.topFiles {
                if y + 17 > bottom { newPage(); head() }
                text(f.name, xName, y, 9, ink, bold: true, maxWidth: 182)
                text(f.folder, xFolder, y, 8.5, sub, maxWidth: 192, middle: true)
                text(FileOps.formatDate(f.modified), xMod, y, 8.5, sub, maxWidth: 80)
                text(size(f.size), xSize, y, 9, ink, bold: true, right: true)
                y += 17
            }
            y += 16
        }

        private func types() {
            guard !d.types.isEmpty else { return }
            let shown = 14
            var rows = d.types.prefix(shown).map { (label: $0.ext.isEmpty ? Loc.t("PdfNoExt") : $0.ext, size: $0.size, count: $0.count) }
            if d.types.count > shown {
                let rest = d.types.dropFirst(shown)
                rows.append((Loc.f("PdfOtherTypes", count(Int64(rest.count))), rest.reduce(0) { $0 + $1.size },
                             rest.reduce(0) { $0 + $1.count }))
            }
            let total = d.types.reduce(Int64(0)) { $0 + $1.size }

            sectionTitle(Loc.t("PdfTypes"), needBelow: 18 * 3 + 18)
            let xType = margin, xBar = margin + 150, xPct = margin + 385, xFiles = margin + 450, xSize = pageW - margin
            func head() {
                tableHeader([Col(text: Loc.t("PdfColType"), x: xType, w: 140, right: false),
                             Col(text: Loc.t("PdfColShare"), x: xBar, w: 200, right: false),
                             Col(text: Loc.t("PdfColFiles"), x: xFiles - 60, w: 60, right: true),
                             Col(text: Loc.t("PdfColSize"), x: xSize - 60, w: 60, right: true)])
            }
            head()
            for r in rows {
                if y + 17 > bottom { newPage(); head() }
                let p = total > 0 ? Double(r.size) * 100 / Double(total) : 0
                text(r.label, xType, y, 9.5, ink, bold: true, maxWidth: 140)
                shareBar(xBar, y + 4.5, 200, p, accent)
                text(pct(p), xPct, y, 8.5, sub, right: true)
                text(count(r.count), xFiles, y, 9, sub, right: true)
                text(size(r.size), xSize, y, 9.5, ink, bold: true, right: true)
                y += 17
            }
            y += 16
        }

        private func ages() {
            let total = d.ages.reduce(Int64(0)) { $0 + $1.size }
            guard total > 0 else { return }
            sectionTitle(Loc.t("PdfAges"), needBelow: 44 + CGFloat(d.ages.count) * 17)

            // Thanh xếp chồng: cả cây theo tuổi file
            var x = margin
            for (i, a) in d.ages.enumerated() {
                let w = contentW * CGFloat(a.size) / CGFloat(total)
                rect(x, y, w, 12, ageColors[i % ageColors.count])
                x += w
            }
            y += 22

            let xPct = margin + 330, xFiles = margin + 430, xSize = pageW - margin
            tableHeader([Col(text: Loc.t("PdfColModified"), x: margin, w: 200, right: false),
                         Col(text: Loc.t("PdfColShare"), x: xPct - 60, w: 60, right: true),
                         Col(text: Loc.t("PdfColFiles"), x: xFiles - 60, w: 60, right: true),
                         Col(text: Loc.t("PdfColSize"), x: xSize - 60, w: 60, right: true)])
            for (i, a) in d.ages.enumerated() {
                rect(margin, y + 3, 8, 8, ageColors[i % ageColors.count], radius: 2)
                text(Loc.t("Age\(min(i, d.ages.count - 1))"), margin + 16, y, 9.5, ink, maxWidth: 200)
                text(pct(Double(a.size) * 100 / Double(total)), xPct, y, 8.5, sub, right: true)
                text(count(a.count), xFiles, y, 9, sub, right: true)
                text(size(a.size), xSize, y, 9.5, ink, bold: true, right: true)
                y += 17
            }
            y += 16
        }

        private func notes() {
            guard d.statsStale else { return }
            ensure(40)
            y += paragraph(Loc.t("PdfStale"), margin, y, width: contentW, size: 8.5, color: sub) + 6
        }
    }
}
