import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import DiskatCore

// Sinh AppIcon.icns từ logo vector (LogoArt), theo lưới biểu tượng macOS:
// khung 1024, phần thân 824 x 824 ở giữa, có đổ bóng nhẹ.
//   swift run make-icon [Resources/AppIcon.icns]

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
let iconset = NSTemporaryDirectory() + "Diskat-\(UUID().uuidString).iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(atPath: iconset) }

func render(_ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let unit = CGFloat(px) / 1024
    let body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 20 * unit,
                  color: CGColor(gray: 0, alpha: 0.3))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    LogoArt.draw(in: ctx, rect: body)
    ctx.endTransparencyLayer()
    return ctx.makeImage()!
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let url = URL(fileURLWithPath: iconset + "/" + name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, render(points * scale), nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(name)") }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output)")
