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

/// Bản đồ dung lượng dạng "squarified treemap", 2 cấp. Nội dung được vẽ một lần vào bitmap;
/// draw(_:) chỉ chép bitmap và vẽ viền ô đang rê chuột nên di chuột rất nhẹ.
final class TreemapView: NSView {
    struct Item {
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

    var onClick: ((Item) -> Void)?
    var onDoubleClick: ((Item) -> Void)?
    var onHover: ((Item?) -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private(set) var root: DirNode?
    private var items: [Item] = []
    private var hover: Int?

    // File nằm trực tiếp trong root: tải ở luồng nền, giữ tối đa maxRootFiles file lớn nhất
    private nonisolated static let maxRootFiles = 1000
    private var rootFiles: (items: [FileItem], restCount: Int, restSize: Int64)?
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
                let result = Self.loadFiles(path)
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

    private nonisolated static func loadFiles(_ path: String) -> (items: [FileItem], restCount: Int, restSize: Int64) {
        var all = FileOps.listFiles(path)
        all.sort { $0.size > $1.size }
        guard all.count > maxRootFiles else { return (all, 0, 0) }
        let rest = all[maxRootFiles...].reduce(Int64(0)) { $0 + $1.size }
        let restCount = all.count - maxRootFiles
        all.removeSubrange(maxRootFiles...)
        return (all, restCount, rest)
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

    // ================= Bảng màu =================

    private static let baseColors: [UInt32] = [
        0x4F8DF5, 0x2FB59C, 0x6CB84A, 0xF2B12E, 0xF07F3C, 0xE5565B,
        0xD95CA8, 0x9B6CE0, 0x5C6BD8, 0x2EA8D6, 0xA3B835, 0xB07A52,
    ]
    private static let fileColor: UInt32 = 0x8E9AAF

    private static func mix(_ c: UInt32, _ target: CGFloat, _ t: CGFloat) -> CGColor {
        func ch(_ shift: UInt32) -> CGFloat {
            let v = CGFloat((c >> shift) & 0xFF) / 255
            return v + (target - v) * t
        }
        return CGColor(srgbRed: ch(16), green: ch(8), blue: ch(0), alpha: 1)
    }

    private static var gradients: [Int: CGGradient] = [:]

    private static func gradient(color: Int, depth: Int) -> CGGradient {
        let key = color * 4 + min(depth, 1)
        if let g = gradients[key] { return g }
        var base = color < 0 ? fileColor : baseColors[color % baseColors.count]
        if depth > 0 {
            let lighter = mix(base, 1, 0.25).components!
            base = UInt32(lighter[0] * 255) << 16 | UInt32(lighter[1] * 255) << 8 | UInt32(lighter[2] * 255)
        }
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [mix(base, 1, 0.22), mix(base, 0, 0.12)] as CFArray, locations: [0, 1])!
        gradients[key] = g
        return g
    }

    // ================= Vẽ =================

    private func render() {
        items.removeAll(keepingCapacity: true)
        let bounds = self.bounds
        renderedSize = bounds.size
        guard let root, bounds.width >= 4, bounds.height >= 4 else {
            content = nil
            needsDisplay = true
            return
        }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pw = Int(bounds.width * scale), ph = Int(bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        // Trục y hướng xuống, đơn vị điểm
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.current = previous }

        let files = filesFor === root ? rootFiles : nil
        let top = TreemapLayout.entries(of: root, files: files)
        var colorIndex = 0

        TreemapLayout.squarify(top.map(\.size), in: bounds) { k, r in
            let e = top[k]
            let color = e.node != nil ? colorIndex : -1
            if e.node != nil { colorIndex += 1 }
            let item = Item(node: e.node, owner: root, filePath: e.filePath, label: e.label, size: e.size,
                            rect: r, depth: 0, color: color, isGroup: e.isGroup)
            items.append(item)
            let nested = hasNested(item)
            drawCell(ctx, item, nested: nested)

            // Cấp 2: vẽ các thư mục con bên trong nếu đủ chỗ
            guard nested, let node = e.node else { return }
            let inner = CGRect(x: r.minX + 3, y: r.minY + 20, width: r.width - 6, height: r.height - 23)
            guard inner.width > 8, inner.height > 8 else { return }
            let sub = TreemapLayout.entries(of: node, files: nil)
            TreemapLayout.squarify(sub.map(\.size), in: inner) { k2, r2 in
                let s = sub[k2]
                let child = Item(node: s.node, owner: node, filePath: nil, label: s.label, size: s.size,
                                 rect: r2, depth: 1, color: s.node != nil ? color : -1, isGroup: s.isGroup)
                items.append(child)
                drawCell(ctx, child, nested: false)
            }
        }

        content = ctx.makeImage()
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

    private func hasNested(_ it: Item) -> Bool {
        it.depth == 0 && it.node != nil && it.rect.width >= 70 && it.rect.height >= 50 && !(it.node!.children.isEmpty)
    }

    private static let borderColor = CGColor(gray: 1, alpha: 0.75)
    private static let headerColor = CGColor(gray: 0, alpha: 0.25)
    private static let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.35)
        s.shadowOffset = NSSize(width: 0, height: -0.5)
        s.shadowBlurRadius = 1
        return s
    }()

    private func drawCell(_ ctx: CGContext, _ it: Item, nested: Bool) {
        let r = it.rect
        guard r.width >= 0.6, r.height >= 0.6 else { return }

        ctx.saveGState()
        ctx.clip(to: r)
        ctx.drawLinearGradient(Self.gradient(color: it.color, depth: it.depth),
                               start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
        if nested {
            ctx.setFillColor(Self.headerColor)
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: min(20, r.height)))
        }
        ctx.restoreGState()
        if r.width > 3 && r.height > 3 {
            ctx.setStrokeColor(Self.borderColor)
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
            .paragraphStyle: para, .shadow: Self.textShadow,
        ]
        let sizeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: nested ? 11 : fontSize - 1), .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .paragraphStyle: para, .shadow: Self.textShadow,
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
