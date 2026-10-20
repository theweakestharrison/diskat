import Foundation

/// Giao diện: theo hệ thống (mặc định), luôn sáng hoặc luôn tối.
public enum AppTheme: String, CaseIterable, Sendable {
    case system, light, dark
}

/// Tùy chọn của người dùng, lưu trong UserDefaults (ngôn ngữ do Loc giữ riêng).
public enum Settings {
    private static let defaults = UserDefaults.standard

    /// Tự kiểm tra bản mới khi mở app. Mặc định TẮT: Diskat không kết nối mạng nếu người dùng không yêu cầu.
    public static var checkForUpdatesOnStartup: Bool {
        get { defaults.bool(forKey: "checkForUpdatesOnStartup") }
        set { defaults.set(newValue, forKey: "checkForUpdatesOnStartup") }
    }

    public static var lastUpdateCheck: Date? {
        get { defaults.object(forKey: "lastUpdateCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastUpdateCheck") }
    }

    /// Lưu cây thư mục sau mỗi lần quét xong (chỉ trên máy này, ScanSnapshot) để so sánh về sau. Mặc định bật.
    public static var saveScanHistory: Bool {
        get { defaults.object(forKey: "saveScanHistory") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "saveScanHistory") }
    }

    public static var theme: AppTheme {
        get { defaults.string(forKey: "theme").flatMap(AppTheme.init(rawValue:)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "theme") }
    }
}
