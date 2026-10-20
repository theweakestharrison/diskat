import AppKit
import UniformTypeIdentifiers
import DiskatCore

/// Mở / hiển thị trong Finder, sao chép đường dẫn.
@MainActor
enum Finder {
    /// Mở cửa sổ Finder hiển thị nội dung thư mục (không "chạy" gói .app như NSWorkspace.open).
    static func showFolder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    /// Mở thư mục chứa và chọn sẵn mục này.
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Mở bằng ứng dụng mặc định.
    static func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

/// Biểu tượng file / thư mục của hệ thống (bộ đệm theo phần mở rộng).
@MainActor
enum Icons {
    private static func sized(_ image: NSImage, _ size: CGFloat = 16) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: size, height: size)
        return copy
    }

    static let folder = sized(NSWorkspace.shared.icon(for: .folder))
    static let volume = sized(NSWorkspace.shared.icon(for: .volume))
    static let summary: NSImage = {
        let img = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)!
        return img.withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) ?? img
    }()

    /// Thư mục không đọc được: biểu tượng thư mục mờ kèm ổ khóa đỏ.
    static let lockedFolder: NSImage = {
        let base = folder
        let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold).applying(.init(paletteColors: [Theme.dangerNS])))!
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.55)
            let s = lock.size
            lock.draw(in: NSRect(x: rect.maxX - s.width, y: 0, width: s.width, height: s.height))
            return true
        }
    }()

    private static var byExtension: [String: NSImage] = [:]

    static func file(named name: String) -> NSImage {
        let ext = (name as NSString).pathExtension.lowercased()
        if let cached = byExtension[ext] { return cached }
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        let icon = sized(NSWorkspace.shared.icon(for: type))
        byExtension[ext] = icon
        return icon
    }

    private static var packageTypes: [String: Bool] = [:]
    private static var packageIcons: [String: NSImage] = [:]

    /// Thư mục là gói (.app, .photoslibrary...) thì dùng biểu tượng thật của gói (ứng dụng có biểu tượng riêng).
    static func folder(named name: String, path: () -> String) -> NSImage {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return folder }
        let isPackage = packageTypes[ext] ?? {
            let p = UTType(filenameExtension: ext, conformingTo: .directory)?.conforms(to: .package) ?? false
            packageTypes[ext] = p
            return p
        }()
        guard isPackage else { return folder }
        let full = path()
        if let cached = packageIcons[full] { return cached }
        if packageIcons.count > 2000 { packageIcons.removeAll() }
        let icon = sized(NSWorkspace.shared.icon(forFile: full))
        packageIcons[full] = icon
        return icon
    }
}
