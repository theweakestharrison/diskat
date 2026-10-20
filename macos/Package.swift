// swift-tools-version: 6.0
import PackageDescription

// Diskat cho macOS. Mở thư mục này bằng Xcode (File > Open > Package.swift) để chạy/gỡ lỗi,
// hoặc dùng scripts/build-app.sh để tạo Diskat.app.
let package = Package(
    name: "Diskat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Diskat", targets: ["Diskat"]),
    ],
    targets: [
        // Bộ quét, mô hình cây thư mục, thao tác file, bản địa hóa: không phụ thuộc giao diện
        .target(name: "DiskatCore"),
        // Ứng dụng SwiftUI + AppKit
        .executableTarget(name: "Diskat", dependencies: ["DiskatCore"]),
        // Sinh AppIcon.icns từ logo vector (swift run make-icon)
        .executableTarget(name: "make-icon", dependencies: ["DiskatCore"], path: "Tools/make-icon"),
        .testTarget(name: "DiskatCoreTests", dependencies: ["DiskatCore"]),
    ],
    swiftLanguageModes: [.v5]
)
