import Foundation
import os

/// Khóa chung bảo vệ dữ liệu quét của mọi DirNode (dung lượng, danh sách con, cờ trạng thái).
/// Mỗi luồng quét chỉ giữ khóa một lần cho mỗi thư mục nên tranh chấp rất thấp;
/// giao diện giữ khóa trong vài chục nano giây cho mỗi lần đọc.
let treeLock = OSAllocatedUnfairLock()

/// Một thư mục trong cây đã quét. Các bộ đếm tổng hợp (size/fileCount/dirCount)
/// được cộng dồn từ nhiều luồng quét song song, luôn dưới `treeLock`.
public final class DirNode: @unchecked Sendable {
    public let name: String
    public internal(set) weak var parent: DirNode?
    /// Thời điểm sửa đổi (giây kể từ 1970).
    public let modified: Double
    /// Điểm gắn (mount point) của ổ khác: được liệt kê nhưng không quét vào, tránh đếm trùng.
    public let isMount: Bool

    // ----- Dữ liệu quét: chỉ đọc/ghi khi giữ treeLock -----
    var _size: Int64 = 0
    var _fileCount: Int64 = 0
    var _dirCount: Int64 = 0
    var _ownSize: Int64 = 0
    var _ownFiles = 0
    var _children: [DirNode] = []
    var _scanned = false
    var _accessDenied = false

    // Trạng thái giao diện (chỉ dùng trên luồng chính)
    public var isExpanded = false

    init(name: String, parent: DirNode?, modified: Double, isMount: Bool = false) {
        self.name = name
        self.parent = parent
        self.modified = modified
        self.isMount = isMount
        // Mount point coi như đã quét xong (rỗng)
        _scanned = isMount
    }

    // ----- Đọc an toàn từ mọi luồng -----

    /// Tổng dung lượng, bao gồm toàn bộ cây con.
    public var size: Int64 { treeLock.withLockUnchecked { _size } }
    public var fileCount: Int64 { treeLock.withLockUnchecked { _fileCount } }
    public var dirCount: Int64 { treeLock.withLockUnchecked { _dirCount } }
    /// Chỉ các file nằm trực tiếp trong thư mục này.
    public var ownSize: Int64 { treeLock.withLockUnchecked { _ownSize } }
    public var ownFiles: Int { treeLock.withLockUnchecked { _ownFiles } }
    /// Được gán đúng một lần khi quét xong thư mục (danh sách hoàn chỉnh).
    public var children: [DirNode] { treeLock.withLockUnchecked { _children } }
    public var isScanned: Bool { treeLock.withLockUnchecked { _scanned } }
    public var isAccessDenied: Bool { treeLock.withLockUnchecked { _accessDenied } }

    public var fullPath: String {
        guard let parent else { return name }
        let base = parent.fullPath
        return base.hasSuffix("/") ? base + name : base + "/" + name
    }

    public var depth: Int {
        var d = 0
        var p = parent
        while let n = p { d += 1; p = n.parent }
        return d
    }

    public func isAncestor(of other: DirNode) -> Bool {
        var p = other.parent
        while let n = p {
            if n === self { return true }
            p = n.parent
        }
        return false
    }

    // ----- Ghi kết quả quét -----

    /// Luồng quét gọi đúng một lần cho mỗi thư mục: công bố danh sách con và cộng dồn lên các thư mục cha.
    func publishScan(ownSize: Int64, ownFiles: Int, children: [DirNode], denied: Bool) {
        let dirs = Int64(children.count)
        treeLock.withLockUnchecked {
            _ownSize = ownSize
            _ownFiles = ownFiles
            _children = children
            _accessDenied = denied
            _scanned = true
            var p: DirNode? = self
            while let n = p {
                n._size += ownSize
                n._fileCount += Int64(ownFiles)
                n._dirCount += dirs
                p = n.parent
            }
        }
    }

    /// Thay nội dung node bằng kết quả quét lại (`fresh` là gốc của lần quét mới
    /// trên cùng đường dẫn) và điều chỉnh tổng của các thư mục cha.
    public func adopt(_ fresh: DirNode) {
        treeLock.withLockUnchecked {
            let dSize = fresh._size - _size
            let dFiles = fresh._fileCount - _fileCount
            let dDirs = fresh._dirCount - _dirCount
            _size = fresh._size
            _fileCount = fresh._fileCount
            _dirCount = fresh._dirCount
            _ownSize = fresh._ownSize
            _ownFiles = fresh._ownFiles
            _accessDenied = fresh._accessDenied
            _scanned = true
            for c in fresh._children { c.parent = self }
            _children = fresh._children
            var p = parent
            while let n = p {
                n._size += dSize
                n._fileCount += dFiles
                n._dirCount += dDirs
                p = n.parent
            }
        }
    }

    /// Gỡ node khỏi cây (sau khi xóa) và trừ dung lượng ở tất cả thư mục cha.
    public func detach() {
        treeLock.withLockUnchecked {
            guard let parent else { return }
            self.parent = nil
            // Không còn trong danh sách con (ví dụ cha vừa được quét lại): tổng của cha đã không tính node này
            guard let idx = parent._children.firstIndex(where: { $0 === self }) else { return }
            parent._children.remove(at: idx)
            let size = _size, files = _fileCount, dirs = _dirCount + 1
            var p: DirNode? = parent
            while let n = p {
                n._size -= size
                n._fileCount -= files
                n._dirCount -= dirs
                p = n.parent
            }
        }
    }

    /// True nếu node đang nằm trong cây có gốc là `root` (chưa bị gỡ ra khi xóa).
    public func isAttached(to root: DirNode) -> Bool {
        var p = self
        while let up = p.parent { p = up }
        return p === root
    }

    /// False nếu có thư mục con chưa quét xong hoặc không đọc được, tức dung lượng có thể thiếu.
    public func isFullyScanned() -> Bool {
        treeLock.withLockUnchecked {
            var stack: [DirNode] = [self]
            while let n = stack.popLast() {
                if !n._scanned || n._accessDenied { return false }
                for c in n._children where !c.isMount { stack.append(c) }
            }
            return true
        }
    }

    /// Trừ dung lượng một file đã bị xóa khỏi thư mục này.
    public func removeFile(size: Int64) {
        treeLock.withLockUnchecked {
            _ownSize -= size
            _ownFiles -= 1
            var p: DirNode? = self
            while let n = p {
                n._size -= size
                n._fileCount -= 1
                p = n.parent
            }
        }
    }
}

extension DirNode: CustomStringConvertible {
    public var description: String { name }
}
