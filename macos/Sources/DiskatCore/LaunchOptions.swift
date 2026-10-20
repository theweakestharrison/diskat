import Foundation

/// Tham số dòng lệnh (giống bản Windows):
///   Diskat [thư mục] [--pdf file.pdf] [--csv thư-mục.csv] [--files-csv file.csv] [--lang vi] [--compare] [--quit]
/// Thư mục được quét ngay; các file xuất được ghi sau khi quét xong; --quit đóng Diskat khi đã xuất xong.
/// --compare: so với lần quét đã lưu gần nhất của thư mục đó (báo cáo PDF có thêm phần thay đổi).
/// Trên macOS chạy file thực thi trong gói: /Applications/Diskat.app/Contents/MacOS/Diskat ~/Projects --pdf r.pdf --quit
public struct LaunchOptions: Sendable {
    public var scanPath: String?
    public var pdfPath: String?
    public var foldersCsvPath: String?
    public var filesCsvPath: String?
    public var lang: String?
    public var quit = false
    public var compare = false

    public init() {}

    public var hasExports: Bool { pdfPath != nil || foldersCsvPath != nil || filesCsvPath != nil }

    public static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 0
        func next() -> String? {
            guard i + 1 < args.count else { return nil }
            i += 1
            return absolute(args[i])
        }
        while i < args.count {
            let a = args[i]
            switch a.lowercased() {
            case "--pdf": o.pdfPath = next()
            case "--csv": o.foldersCsvPath = next()
            case "--files-csv": o.filesCsvPath = next()
            case "--lang":
                if i + 1 < args.count { i += 1; o.lang = args[i].lowercased() }
            case "--quit": o.quit = true
            case "--compare": o.compare = true
            default:
                // "-NSDocumentRevisionsDebugMode YES" của Xcode và các tham số AppKit khác bắt đầu bằng "-"
                if a.hasPrefix("-") {
                    if !a.hasPrefix("--"), i + 1 < args.count, !args[i + 1].hasPrefix("-") { i += 1 }
                } else if o.scanPath == nil {
                    o.scanPath = a
                }
            }
            i += 1
        }
        return o
    }

    /// Đường dẫn file xuất: tương đối thì tính từ thư mục hiện hành.
    private static func absolute(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let full = expanded.hasPrefix("/") ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
        return URL(fileURLWithPath: full).standardized.path
    }
}
