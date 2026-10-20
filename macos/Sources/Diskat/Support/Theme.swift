import AppKit
import SwiftUI

/// Màu thương hiệu (giống Themes/Styles.xaml bản Windows) và màu của thanh phần trăm.
enum Theme {
    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static let accentNS = rgb(0x2F6FED)
    static let dangerNS = rgb(0xD93B3B)
    static let amberNS = rgb(0xE8A317)

    // Cột "Thay đổi": dùng thêm dung lượng (đỏ cam) / đã giải phóng (xanh lá), đủ tương phản ở cả hai giao diện
    static let growNS = NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(0xFF8F66) : rgb(0xB4380F)
    }
    static let shrinkNS = NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(0x5FD38D) : rgb(0x146C36)
    }

    static let accent = Color(nsColor: accentNS)
    static let danger = Color(nsColor: dangerNS)
    static let amber = Color(nsColor: amberNS)

    /// Rãnh của thanh tiến trình mảnh
    static let trackNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.12) : rgb(0xE6EAF1)
    }
    static let track = Color(nsColor: trackNS)

    private static let bars = [rgb(0x4CAF7D), rgb(0x7CB342), rgb(0xE8A317), rgb(0xEF7B2D), rgb(0xE04A3F)]

    /// Màu thanh "% thư mục cha": xanh khi nhỏ, đỏ khi chiếm phần lớn.
    static func barColor(percent p: Double) -> NSColor {
        p < 10 ? bars[0] : p < 25 ? bars[1] : p < 50 ? bars[2] : p < 75 ? bars[3] : bars[4]
    }

    /// Màu thanh dung lượng ổ đĩa
    static func driveColor(percent p: Double) -> Color {
        p >= 90 ? danger : p >= 75 ? amber : accent
    }
}
