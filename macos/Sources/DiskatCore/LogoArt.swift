import CoreGraphics

/// Logo Diskat (giống Themes/Logo.xaml của bản Windows): mặt mèo là một biểu đồ vành khuyên,
/// phần vàng = dung lượng đã dùng, phần trắng = còn trống. Hệ tọa độ gốc 36 x 36, trục y hướng xuống.
public enum LogoArt {
    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static let head: CGPath = {
        let h = CGMutablePath()
        h.move(to: p(7.2, 22))
        h.addCurve(to: p(9.6, 14.1), control1: p(7.2, 18.6), control2: p(8.2, 15.9))
        h.addLine(to: p(8.9, 6.4))
        h.addCurve(to: p(10.2, 5.6), control1: p(8.85, 5.6), control2: p(9.6, 5.2))
        h.addLine(to: p(16, 9.9))
        h.addCurve(to: p(18, 9.75), control1: p(16.65, 9.8), control2: p(17.3, 9.75))
        h.addCurve(to: p(20, 9.9), control1: p(18.7, 9.75), control2: p(19.35, 9.8))
        h.addLine(to: p(25.8, 5.6))
        h.addCurve(to: p(27.1, 6.4), control1: p(26.4, 5.2), control2: p(27.15, 5.6))
        h.addLine(to: p(26.4, 14.1))
        h.addCurve(to: p(28.8, 22), control1: p(27.8, 15.9), control2: p(28.8, 18.6))
        h.addCurve(to: p(18, 31), control1: p(28.8, 27.6), control2: p(24, 31))
        h.addCurve(to: p(7.2, 22), control1: p(12, 31), control2: p(7.2, 27.6))
        h.closeSubpath()
        return h
    }()

    private static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    private static let face = CGPath(ellipseIn: CGRect(x: 18 - 6.6, y: 21.6 - 5.9, width: 13.2, height: 11.8), transform: nil)
    /// Lát "đã dùng": từ đỉnh đầu theo chiều kim đồng hồ tới góc dưới phải (gồm cả tai phải)
    private static let usedWedge = polygon([p(18, 21.6), p(18.6, 0), p(40, 0), p(40, 30), p(33, 30.5)])
    /// Khe hở mảnh giữa hai lát, giống biểu đồ thật
    private static let gaps: CGPath = {
        let g = CGMutablePath()
        g.addPath(polygon([p(17.45, 21.6), p(18.05, 0), p(19.15, 0), p(18.55, 21.6)]))
        g.addPath(polygon([p(17.72, 22.07), p(32.72, 30.97), p(33.28, 30.03), p(18.28, 21.13)]))
        return g
    }()

    private static let ring = head.subtracting(face)
    private static let freePart = ring.subtracting(usedWedge).subtracting(gaps)
    private static let usedPart = ring.intersection(usedWedge).subtracting(gaps)

    private static func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Vẽ logo vào `rect`. `flipped`: true nếu ngữ cảnh có trục y hướng xuống (NSView lật, bitmap đã lật).
    public static func draw(in ctx: CGContext, rect: CGRect, flipped: Bool = false) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let s = min(rect.width, rect.height) / 36
        if flipped {
            ctx.translateBy(x: rect.minX, y: rect.minY)
            ctx.scaleBy(x: s, y: s)
        } else {
            ctx.translateBy(x: rect.minX, y: rect.minY + 36 * s)
            ctx.scaleBy(x: s, y: -s)
        }

        // Nền bo góc, chuyển màu chéo
        let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 36, height: 36), cornerWidth: 9, cornerHeight: 9, transform: nil)
        ctx.saveGState()
        ctx.addPath(bg)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [color(0x5B8CFF), color(0x2E4FD8)] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: p(0, 0), end: p(36, 36), options: [])
        }
        ctx.restoreGState()

        // Phần còn trống (trắng) và phần đã dùng (vàng)
        ctx.setFillColor(color(0xFFFFFF))
        ctx.addPath(freePart)
        ctx.fillPath()
        ctx.setFillColor(color(0xFFB938))
        ctx.addPath(usedPart)
        ctx.fillPath()

        // Mắt
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: 15.4 - 1.25, y: 21.3 - 1.6, width: 2.5, height: 3.2))
        ctx.fillEllipse(in: CGRect(x: 20.6 - 1.25, y: 21.3 - 1.6, width: 2.5, height: 3.2))

        // Mũi
        ctx.setFillColor(color(0xFF9AA8))
        ctx.addPath(polygon([p(17.1, 23.6), p(18.9, 23.6), p(18, 24.6)]))
        ctx.fillPath()
    }

    /// Ảnh logo dạng bitmap vuông `pixels` x `pixels`.
    public static func image(pixels: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(in: ctx, rect: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return ctx.makeImage()
    }
}
