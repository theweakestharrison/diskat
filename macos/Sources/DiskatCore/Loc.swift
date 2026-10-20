import Foundation
import Observation

/// Bản địa hóa: mỗi ngôn ngữ là một file Lang/Strings+<mã>.swift, mặc định theo ngôn ngữ hệ thống
/// (nếu có bản dịch), không thì tiếng Anh. Chuỗi thiếu trong một bản dịch sẽ lấy từ tiếng Anh.
/// Chỗ giữ chỗ dùng cú pháp như bản Windows: {0}, {1:0.0} (số chữ số thập phân), {0:X} (hệ 16).
///
/// `Loc.t` đọc `lang` của một đối tượng @Observable nên mọi view SwiftUI gọi nó sẽ tự vẽ lại khi đổi ngôn ngữ.
@Observable
public final class Loc {
    public struct Language: Hashable, Sendable {
        public let code: String
        public let name: String
    }

    public static let defaultLanguage = "en"

    /// Thêm ngôn ngữ mới: tạo Strings+<mã>.swift rồi thêm vào hai danh sách dưới đây.
    public static let languages: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "vi", name: "Tiếng Việt"),
        Language(code: "zh", name: "简体中文"),
        Language(code: "ja", name: "日本語"),
        Language(code: "ko", name: "한국어"),
        Language(code: "es", name: "Español"),
        Language(code: "pt", name: "Português"),
        Language(code: "de", name: "Deutsch"),
        Language(code: "fr", name: "Français"),
        Language(code: "ru", name: "Русский"),
        Language(code: "id", name: "Bahasa Indonesia"),
    ]

    public static let tables: [String: [String: String]] = [
        "en": Strings.en, "vi": Strings.vi, "zh": Strings.zh, "ja": Strings.ja, "ko": Strings.ko,
        "es": Strings.es, "pt": Strings.pt, "de": Strings.de, "fr": Strings.fr, "ru": Strings.ru,
        "id": Strings.id,
    ]

    public static let shared = Loc()
    private static let settingsKey = "language"

    public private(set) var lang: String

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.settingsKey)
        if let saved, Self.tables[saved] != nil {
            lang = saved
        } else {
            // Lần chạy đầu: ngôn ngữ ưu tiên đầu tiên của hệ thống có bản dịch
            lang = Locale.preferredLanguages.lazy
                .map { String($0.prefix(2)) }
                .first { Self.tables[$0] != nil } ?? Self.defaultLanguage
        }
    }

    public static var lang: String { shared.lang }

    /// Dùng ngôn ngữ này cho lần chạy hiện tại mà không lưu lại (tham số --lang).
    public static func useForSession(_ code: String) {
        if tables[code] != nil { shared.lang = code }
    }

    public static func setLanguage(_ code: String) {
        guard code != shared.lang, tables[code] != nil else { return }
        shared.lang = code
        UserDefaults.standard.set(code, forKey: settingsKey)
    }

    public static func t(_ key: String) -> String {
        if let v = tables[shared.lang]?[key] { return v }
        return Strings.en[key] ?? key
    }

    public static func f(_ key: String, _ args: Any...) -> String {
        format(t(key), args)
    }

    /// Thay {n} / {n:0.0} / {n:X} bằng tham số thứ n.
    static func format(_ template: String, _ args: [Any]) -> String {
        var out = ""
        var i = template.startIndex
        while i < template.endIndex {
            let ch = template[i]
            guard ch == "{", let close = template[i...].firstIndex(of: "}") else {
                out.append(ch)
                i = template.index(after: i)
                continue
            }
            let spec = template[template.index(after: i)..<close]
            let parts = spec.split(separator: ":", maxSplits: 1)
            guard let first = parts.first, let n = Int(first), n >= 0, n < args.count else {
                out.append(ch)
                i = template.index(after: i)
                continue
            }
            out += render(args[n], parts.count > 1 ? String(parts[1]) : nil)
            i = template.index(after: close)
        }
        return out
    }

    private static func render(_ value: Any, _ fmt: String?) -> String {
        guard let fmt else {
            if let d = value as? Double { return String(format: "%g", d) }
            return "\(value)"
        }
        if fmt == "X", let n = value as? Int { return String(n, radix: 16, uppercase: true) }
        if fmt.allSatisfy({ $0 == "0" || $0 == "." }) {
            let decimals = fmt.split(separator: ".").dropFirst().first?.count ?? 0
            let d = (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? Int64).map(Double.init) ?? 0
            return String(format: "%.\(decimals)f", d)
        }
        return "\(value)"
    }
}

/// Bảng chuỗi theo ngôn ngữ (Lang/Strings+<mã>.swift).
public enum Strings {}
