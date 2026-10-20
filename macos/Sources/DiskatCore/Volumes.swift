import Foundation

public struct VolumeInfo: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case `internal`, external, network }

    public var id: String { path }
    public let path: String
    public let name: String
    public let format: String
    public let total: Int64
    public let available: Int64
    public let kind: Kind

    public var used: Int64 { max(0, total - available) }
    public var usedPercent: Double { total > 0 ? Double(used) * 100 / Double(total) : 0 }
}

public enum Volumes {
    private static let keys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsLocalKey,
        .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsBrowsableKey,
        .volumeLocalizedFormatDescriptionKey, .volumeIsRootFileSystemKey,
    ]

    /// Các ổ đang gắn mà người dùng thấy trong Finder (ổ khởi động trước).
    public static func mounted() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var list: [(VolumeInfo, Bool)] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.volumeIsBrowsable == false { continue }
            let total = Int64(v.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }
            // "Dung lượng khả dụng" của Finder: gồm cả phần hệ thống có thể giải phóng (purgeable)
            let important = v.volumeAvailableCapacityForImportantUsage ?? 0
            let available = important > 0 ? important : Int64(v.volumeAvailableCapacity ?? 0)
            let kind: VolumeInfo.Kind = v.volumeIsLocal == false ? .network
                : (v.volumeIsInternal == true && v.volumeIsEjectable != true) ? .internal : .external
            let info = VolumeInfo(path: url.path, name: v.volumeLocalizedName ?? url.lastPathComponent,
                                  format: v.volumeLocalizedFormatDescription ?? "", total: total,
                                  available: min(available, total), kind: kind)
            list.append((info, v.volumeIsRootFileSystem == true || url.path == "/"))
        }
        return list.sorted { a, b in a.1 != b.1 ? a.1 : a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending }
            .map(\.0)
    }
}
