import CryptoKit
import Foundation

public struct UpdateInfo: Sendable {
    public let version: String
    public let url: URL
    /// SHA-256 của file DMG (chữ thường); nil nếu máy chủ chưa công bố, khi đó chỉ mở trang tải
    public let sha256: String?
    public let size: Int64?
    public let notes: URL?
}

/// Kiểm tra và tải bản mới. Chỉ chạy khi người dùng bấm "Kiểm tra cập nhật" hoặc tự bật kiểm tra lúc khởi động.
/// Mỗi lần kiểm tra là một yêu cầu GET tới https://diskat.cc/api/latest/mac, không gửi thông tin gì về máy.
public enum Updater {
    private static let apiURL = URL(string: "https://diskat.cc/api/latest/mac")!
    private static let trustedHost = "diskat.cc"

    /// Phiên bản đang chạy (Info.plist). Biến môi trường DISKAT_FAKE_VERSION dùng để thử luồng cập nhật.
    public static var currentVersion: String {
        if let fake = ProcessInfo.processInfo.environment["DISKAT_FAKE_VERSION"] { return fake }
        // Chạy thẳng file thực thi (swift run) thì không có Info.plist
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// So sánh "1.10.0" với "1.9.2" theo từng số.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private static func isTrusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == trustedHost
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "Diskat/\(currentVersion) (macOS)"]
        return URLSession(configuration: config)
    }()

    private static func responseData(from url: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: url) { data, response, error in
                if let error = error { continuation.resume(throwing: error) }
                else if let data = data, let response = response { continuation.resume(returning: (data, response)) }
                else { continuation.resume(throwing: URLError(.badServerResponse)) }
            }.resume()
        }
    }

    private static func downloadedFile(from url: URL) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.downloadTask(with: url) { temporary, response, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let temporary = temporary, let response = response else {
                    continuation.resume(throwing: URLError(.badServerResponse)); return
                }
                let saved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: temporary, to: saved)
                    continuation.resume(returning: (saved, response))
                } catch { continuation.resume(throwing: error) }
            }.resume()
        }
    }

    /// Trả về thông tin bản mới nếu có bản mới hơn bản đang chạy, ngược lại nil.
    public static func check() async throws -> UpdateInfo? {
        let (data, response) = try await responseData(from: apiURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String, let urlText = json["url"] as? String,
              let url = URL(string: urlText) else {
            throw URLError(.cannotParseResponse)
        }
        Settings.lastUpdateCheck = Date()
        guard isTrusted(url) else { throw URLError(.badURL) }
        let sha = (json["sha256"] as? String).flatMap { $0.count == 64 ? $0.lowercased() : nil }
        let size = (json["size"] as? NSNumber)?.int64Value
        let info = UpdateInfo(version: version, url: url, sha256: sha, size: size.flatMap { $0 > 0 ? $0 : nil },
                              notes: (json["notes"] as? String).flatMap(URL.init(string:)))
        return isNewer(version, than: currentVersion) ? info : nil
    }

    /// Tải file DMG về thư mục Downloads và kiểm tra SHA-256. Trả về đường dẫn file đã tải.
    public static func download(_ info: UpdateInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard isTrusted(info.url), let expected = info.sha256 else { throw URLError(.badURL) }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let target = folder.appendingPathComponent("Diskat-\(info.version).dmg")
        let partial = target.appendingPathExtension("part")
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let out = try FileHandle(forWritingTo: partial)
        var completed = false
        defer {
            try? out.close()
            if !completed { try? FileManager.default.removeItem(at: partial) }
        }

        let (download, response) = try await downloadedFile(from: info.url)
        defer { try? FileManager.default.removeItem(at: download) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let total = info.size ?? (response.expectedContentLength > 0 ? response.expectedContentLength : 0)
        var hasher = SHA256()
        let input = try FileHandle(forReadingFrom: download)
        defer { try? input.close() }
        var received: Int64 = 0
        while let buffer = try input.read(upToCount: 1 << 16), !buffer.isEmpty {
            hasher.update(data: buffer)
            try out.write(contentsOf: buffer)
            received += Int64(buffer.count)
            if total > 0 { progress(Double(received) / Double(total)) }
        }
        try out.close()

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { throw URLError(.cannotDecodeContentData) }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
        completed = true
        progress(1)
        return target
    }
}
