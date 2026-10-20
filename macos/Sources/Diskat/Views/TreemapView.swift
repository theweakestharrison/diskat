import AppKit
import SwiftUI
import DiskatCore

/// Bản đồ dung lượng bọc cho SwiftUI.
struct TreemapCanvas: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> TreemapView {
        let view = TreemapView()
        view.onClick = { [weak model] in model?.mapClicked($0) }
        view.onDoubleClick = { [weak model] in model?.mapDoubleClicked($0) }
        view.onHover = { [weak model] in model?.mapHovered($0) }
        view.menuProvider = { [weak model] in
            guard let model, model.mapClickExact else { return nil }
            return ContextMenus.tree(model)
        }
        model.map = view
        return view
    }

    func updateNSView(_ nsView: TreemapView, context: Context) {}
}

/// Một ô trên bản đồ đã được xếp chỗ.
struct TreemapItem {
    /// Thư mục (nil nếu là file / nhóm file)
    let node: DirNode?
    /// Thư mục chứa
    let owner: DirNode
    /// File đơn lẻ
    let filePath: String?
    let label: String
    let size: Int64
    let rect: CGRect
    let depth: Int
    let color: Int
    let isGroup: Bool
}

/// File nằm trực tiếp trong thư mục gốc của bản đồ (lớn nhất trước) và phần còn lại gộp thành một ô.
typealias TreemapFiles = (items: [FileItem], restCount: Int, restSize: Int64)

/// Vẽ bản đồ dung lượng ("squarified treemap", 2 cấp) vào bitmap: dùng cho màn hình và báo cáo PDF.
@MainActor
enum TreemapRenderer {
    nonisolated static let maxRootFiles = 1000

    nonisolated static func loadFiles(_ path: String) -> TreemapFiles {
        var all = FileOps.listFiles(path)
        all.sort { $0.size > $1.size }
        guard all.count > maxRootFiles else { return (all, 0, 0) }
        let rest = all[maxRootFiles...].reduce(Int64(0)) { $0 + $1.size }
        let restCount = all.count - maxRootFiles
        all.removeSubrange(maxRootFiles...)
        return (all, restCount, rest)
    }

    // ---------------- Bảng màu ----------------

    private static let baseColors: [UInt32] = [
        0x4F8DF5, 0x2FB59C, 0x6CB84A, 0xF2B12E, 0xF07F3C, 0xE5565B,
        0xD95CA8, 0x9B6CE0, 0x5C6BD8, 0x2EA8D6, 0xA3B835, 0xB07A52,
    ]
    private static let fileColor: UInt32 = 0x8E9AAF

    private struct RGB {
        var r, g, b: CGFloat
        init(_ hex: UInt32) {
            r = CGFloat((hex >> 16) & 0xFF) / 255
            g = CGFloat((hex >> 8) & 0xFF) / 255
            b = CGFloat(hex & 0xFF) / 255
        }
        func mix(_ target: CGFloat, _ t: CGFloat) -> RGB {
            var c = self
            c.r += (target - r) * t
            c.g += (target - g) * t
            c.b += (target - b) * t
            return c
        }
        var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    }

    private static var gradients: [Int: CGGradient] = [:]

    private static func gradient(color: Int, depth: Int, dark: Bool) -> CGGradient {
        let key = (color + 1) * 4 + min(depth, 1) * 2 + (dark ? 1 : 0)
        if let g = gradients[key] { return g }
        var c = RGB(color < 0 ? fileColor : baseColors[color % baseColors.count])
        let colors: [CGColor]
        if dark {
            // Nền tối: dịu màu đi để ô không chói và chữ trắng dễ đọc hơn; cấp 2 chỉ sáng lên một chút
            c = c.mix(0, 0.22)
            if depth > 0 { c = c.mix(1, 0.12) }
            colors = [c.mix(1, 0.1).cg, c.mix(0, 0.15).cg]
        } else {
            if depth > 0 { c = c.mix(1, 0.25) }
            colors = [c.mix(1, 0.22).cg, c.mix(0, 0.12).cg]
        }
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
        gradients[key] = g
        return g
    }

    private static let borderLight = CGColor(gray: 1, alpha: 0.75)
    // Nền tối: đường phân cách cùng màu nền bản đồ thay vì lưới trắng
    private static let borderDark = CGColor(srgbRed: 0x18 / 255, green: 0x1B / 255, blue: 0x21 / 255, alpha: 0.88)
    private static let headerColor = CGColor(gray: 0, alpha: 0.25)
    private static let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.35)
        s.shadowOffset = NSSize(width: 0, height: -0.5)
        s.shadowBlurRadius = 1
        return s
    }()

    // ---------------- Bố cục và vẽ ----------------

    /// Vẽ bản đồ cho `root` vào ảnh `size` điểm × `scale`. Trả về ảnh và các ô (toạ độ điểm, gốc trên trái).
    static func render(root: DirNode, files: TreemapFiles?, size: CGSize, scale: CGFloat, dark: Bool,
                       background: CGColor? = nil) -> (image: CGImage?, items: [TreemapItem]) {
        var items: [TreemapItem] = []
        let bounds = CGRect(origin: .zero, size: size)
        guard size.width >= 4, size.height >= 4 else { return (nil, items) }

        let pw = Int(size.width * scale), ph = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return (nil, items) }
        // Trục y hướng xuống, đơn vị điểm
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        if let background {
            ctx.setFillColor(background)
            ctx.fill(bounds)
        }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.current = previous }

        let top = TreemapLayout.entries(of: root, files: files)
        var colorIndex = 0

        TreemapLayout.squarify(top.map(\.size), in: bounds) { k, r in
            let e = top[k]
            let color = e.node != nil ? colorIndex : -1
            if e.node != nil { colorIndex += 1 }
            let item = TreemapItem(node: e.node, owner: root, filePath: e.filePath, label: e.label, size: e.size,
                                   rect: r, depth: 0, color: color, isGroup: e.isGroup)
            items.append(item)
            let nested = hasNested(item)
            drawCell(ctx, item, nested: nested, dark: dark)

            // Cấp 2: vẽ các thư mục con bên trong nếu đủ chỗ
            guard nested, let node = e.node else { return }
            let inner = CGRect(x: r.minX + 3, y: r.minY + 20, width: r.width - 6, height: r.height - 23)
            guard inner.width > 8, inner.height > 8 else { return }
            let sub = TreemapLayout.entries(of: node, files: nil)
            TreemapLayout.squarify(sub.map(\.size), in: inner) { k2, r2 in
                let s = sub[k2]
                let child = TreemapItem(node: s.node, owner: node, filePath: nil, label: s.label, size: s.size,
                                        rect: r2, depth: 1, color: s.node != nil ? color : -1, isGroup: s.isGroup)
                items.append(child)
                drawCell(ctx, child, nested: false, dark: dark)
            }
        }
        return (ctx.makeImage(), items)
    }

    private static func hasNested(_ it: TreemapItem) -> Bool {
        guard it.depth == 0, let node = it.node else { return false }
        return it.rect.width >= 70 && it.rect.height >= 50 && !node.children.isEmpty
    }

    private static func drawCell(_ ctx: CGContext, _ it: TreemapItem, nested: Bool, dark: Bool) {
        let r = it.rect
        guard r.width >= 0.6, r.height >= 0.6 else { return }

        ctx.saveGState()
        ctx.clip(to: r)
        ctx.drawLinearGradient(gradient(color: it.color, depth: it.depth, dark: dark),
                               start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
        if nested {
            ctx.setFillColor(headerColor)
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: min(20, r.height)))
        }
        ctx.restoreGState()
        if r.width > 3 && r.height > 3 {
            ctx.setStrokeColor(dark ? borderDark : borderLight)
            ctx.setLineWidth(1)
            ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
        }

        guard r.width >= 44, r.height >= 16 else { return }
        let fontSize: CGFloat = it.depth == 0 ? 12 : 11
        let sizeText = FileOps.formatSize(it.size)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: NSColor.white,
            .paragraphStyle: para, .shadow: textShadow,
        ]
        let sizeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: nested ? 11 : fontSize - 1), .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .paragraphStyle: para, .shadow: textShadow,
        ]

        ctx.saveGState()
        ctx.clip(to: r.insetBy(dx: 2, dy: 0))
        if nested {
            let size = NSAttributedString(string: sizeText, attributes: sizeAttrs)
            let sw = size.size().width
            let showSize = r.width > sw + 60
            let nameWidth = max(1, r.width - (showSize ? sw + 16 : 8))
            NSAttributedString(string: it.label, attributes: nameAttrs)
                .draw(with: CGRect(x: r.minX + 5, y: r.minY + 3, width: nameWidth, height: 16), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            if showSize { size.draw(at: CGPoint(x: r.maxX - sw - 5, y: r.minY + 3.5)) }
        } else {
            NSAttributedString(string: it.label, attributes: nameAttrs)
                .draw(with: CGRect(x: r.minX + 4, y: r.minY + 3, width: max(1, r.width - 8), height: fontSize + 4),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            if r.height >= 34 {
                NSAttributedString(string: sizeText, attributes: sizeAttrs)
                    .draw(with: CGRect(x: r.minX + 4, y: r.minY + fontSize + 7, width: max(1, r.width - 8), height: fontSize + 3),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }
        }
        ctx.restoreGState()
    }
}

/// Bản đồ dung lượng trên màn hình. Nội dung được vẽ một lần vào bitmap (TreemapRenderer);
/// draw(_:) chỉ chép bitmap và vẽ viền ô đang rê chuột nên di chuột rất nhẹ.
final class TreemapView: NSView {
    var onClick: ((TreemapItem) -> Void)?
    var onDoubleClick: ((TreemapItem) -> Void)?
    var onHover: ((TreemapItem?) -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private(set) var root: DirNode?
    private var items: [TreemapItem] = []
    private var hover: Int?

    // File nằm trực tiếp trong root: tải ở luồng nền
    private(set) var rootFiles: TreemapFiles?
    private var filesFor: DirNode?
    private var loadVersion = 0

    private var content: CGImage?
    private var tracking: NSTrackingArea?
    private var renderedSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    /// File của thư mục gốc đã tải xong (dùng lại cho báo cáo PDF).
    var loadedFiles: TreemapFiles? { filesFor === root ? rootFiles : nil }

    // ================= Dữ liệu =================

    func setRoot(_ node: DirNode?) {
        root = node
        rootFiles = nil
        filesFor = nil
        loadVersion += 1
        let version = loadVersion

        if let node, node.ownFiles > 0 {
            // Liệt kê file ở luồng nền: thư mục có hàng trăm nghìn file hoặc ổ mạng không làm đứng giao diện
            let path = node.fullPath
            Task.detached(priority: .userInitiated) {
                let result = TreemapRenderer.loadFiles(path)
                await MainActor.run { [weak self] in
                    guard let self, version == self.loadVersion, self.root === node else { return }
                    self.rootFiles = result
                    self.filesFor = node
                    self.redraw()
                }
            }
        }
        redraw()
    }

    func redraw() {
        setHover(nil, notify: false)
        render()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize != renderedSize { redraw() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redraw()
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    private func render() {
        renderedSize = bounds.size
        if let root {
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let out = TreemapRenderer.render(root: root, files: loadedFiles, size: bounds.size, scale: scale, dark: isDark)
            content = out.image
            items = out.items
        } else {
            content = nil
            items = []
        }
        needsDisplay = true
    }

    private static let hoverFill = NSColor.white.withAlphaComponent(0.18)
    private static let hoverOuter = NSColor.black.withAlphaComponent(0.6)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let content {
            // View lật (y hướng xuống) còn CGImage vẽ theo y hướng lên
            ctx.saveGState()
            ctx.translateBy(x: 0, y: renderedSize.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(content, in: CGRect(origin: .zero, size: renderedSize))
            ctx.restoreGState()
        }
        guard let hover, hover < items.count else { return }
        let r = items[hover].rect.insetBy(dx: 1, dy: 1)
        guard r.width > 0, r.height > 0 else { return }
        Self.hoverFill.setFill()
        r.fill()
        let outer = NSBezierPath(rect: r)
        outer.lineWidth = 4.5
        Self.hoverOuter.setStroke()
        outer.stroke()
        let inner = NSBezierPath(rect: r)
        inner.lineWidth = 2.5
        NSColor.white.setStroke()
        inner.stroke()
    }

    // ================= Chuột =================

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    private func hitTest(at point: CGPoint) -> Int? {
        // Ô cấp 2 nằm sau trong danh sách nên tìm từ cuối
        for i in items.indices.reversed() {
            let r = items[i].rect
            if r.width >= 0.6 && r.height >= 0.6 && r.contains(point) { return i }
        }
        return nil
    }

    private func setHover(_ index: Int?, notify: Bool = true) {
        guard index != hover else { return }
        hover = index
        needsDisplay = true
        if notify { onHover?(index.map { items[$0] }) }
    }

    private func location(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseMoved(with event: NSEvent) {
        setHover(hitTest(at: location(event)))
    }

    override func mouseExited(with event: NSEvent) {
        setHover(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let i = hitTest(at: location(event)) else { return }
        let item = items[i]
        if event.clickCount >= 2 { onDoubleClick?(item) } else { onClick?(item) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = hitTest(at: location(event)) else { return nil }
        onClick?(items[i])
        return menuProvider?()
    }
}
