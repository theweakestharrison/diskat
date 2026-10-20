import AppKit
import DiskatCore

/// Mục "Quét bằng Diskat" trong menu chuột phải của Finder (Dịch vụ / Quick Actions), khai báo ở Info.plist > NSServices.
/// Tương ứng "Scan with Diskat" trong menu chuột phải của Explorer ở bản Windows.
final class ServiceProvider: NSObject {
    @objc func scanWithDiskat(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard let dir = urls.first(where: { FileOps.isDirectory($0.path) }) else { return }
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
            AppModel.shared.startScan(dir.path)
        }
    }
}
