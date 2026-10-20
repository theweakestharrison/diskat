import Foundation
import os

public struct FindResult: Sendable {
    /// Các file khớp lớn nhất (tối đa `max`), lớn trước
    public let files: [FileRecord]
    /// Tổng số file khớp và tổng dung lượng của chúng
    public let total: Int64
    public let totalBytes: Int64
}

/// Tìm file theo mẫu tên, dung lượng tối thiểu và tuổi (lần sửa cuối) trong cả cây thư mục.
/// Chỉ tạo chuỗi đường dẫn cho file khớp; giữ lại tối đa `max` file lớn nhất.
public enum FileFinder {
    /// Số file khớp đã tìm thấy, giao diện đọc định kỳ để hiện tiến độ.
    public final class Counter: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: Int64(0))
        public init() {}
        public var found: Int64 { lock.withLockUnchecked { $0 } }
        func set(_ n: Int64) { lock.withLockUnchecked { $0 = n } }
    }

    /// "*.log; *.tmp" hoặc "*.log *.tmp" là các mẫu riêng; chữ không có * ? được hiểu là "tên có chứa".
    /// Trả về nil nếu không lọc theo tên.
    public static func parsePatterns(_ text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let wild = trimmed.contains("*") || trimmed.contains("?")
        let separators: Set<Character> = wild ? [";", ",", " ", "\t"] : [";", ","]
        let parts = trimmed.split(whereSeparator: { separators.contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let list = parts.map { $0.contains("*") || $0.contains("?") ? $0 : "*" + $0 + "*" }
        return list.isEmpty ? nil : list
    }

    /// `olderThan`: chỉ lấy file sửa lần cuối trước thời điểm này (giây kể từ 1970), nil = mọi ngày.
    public static func find(root: String, patterns: [String]?, minSize: Int64, olderThan: Double?, max: Int,
                            counter: Counter, isCancelled: () -> Bool) throws -> FindResult {
        let cPatterns = patterns?.map { strdup($0)! } ?? []
        defer { cPatterns.forEach { free($0) } }

        let heap = TopFileHeap(capacity: max)
        var total: Int64 = 0, bytes: Int64 = 0
        var stack = [root]
        let lister = DirLister()

        while let dir = stack.popLast() {
            if isCancelled() { throw CancellationError() }
            let isVolumeRoot = dir == "/"
            lister.list(dir) { e in
                if e.isDirectory {
                    // Giống bộ quét: không đi vào ổ khác hay thư mục ảo ở gốc ổ khởi động
                    if e.isMountPoint { return }
                    let name = e.name
                    if isVolumeRoot && DiskScanner.virtualRootDirs.contains(name) { return }
                    stack.append(FileOps.join(dir, name))
                    return
                }
                // Symlink không phải file thật (không chiếm chỗ, xóa đi cũng không được gì)
                if e.type == VLNK.rawValue { return }
                let size = e.allocatedSize
                if size < minSize { return }
                if let olderThan, e.modified >= olderThan { return }
                if !cPatterns.isEmpty && !cPatterns.contains(where: { fnmatch($0, e.namePointer, FNM_CASEFOLD) == 0 }) { return }
                total += 1
                bytes += size
                if size >= heap.threshold {
                    heap.offer(FileRecord(path: FileOps.join(dir, e.name), size: size, modified: e.modified))
                }
            }
            counter.set(total)
        }
        let files = heap.items.sorted { $0.size > $1.size }
        return FindResult(files: files, total: total, totalBytes: bytes)
    }
}
