import Foundation
import os

public struct FileRecord: Sendable, Hashable {
    public let path: String
    public let size: Int64
    public let modified: Double

    public init(path: String, size: Int64, modified: Double) {
        self.path = path
        self.size = size
        self.modified = modified
    }
}

/// Bộ quét song song: nhiều luồng cùng lấy thư mục từ một ngăn xếp chung,
/// liệt kê bằng getattrlistbulk, rồi cộng dồn dung lượng lên các thư mục cha.
public final class DiskScanner: @unchecked Sendable {
    public static let topFileCapacity = 500

    /// Thư mục ảo ở gốc ổ khởi động (đường dẫn kiểu /.vol/<thiết bị>/<inode>): không quét để tránh đếm trùng.
    static let virtualRootDirs: Set<String> = [".vol", ".nofollow", ".resolve"]

    public let root: DirNode

    private let cond = NSCondition()
    /// Thư mục chờ quét kèm đường dẫn đầy đủ (tính sẵn khi đẩy vào, không phải đi ngược lên các thư mục cha)
    private var stack: [(node: DirNode, path: String)] = []
    private var pending = 0
    private var finished = false
    private var cancelled = false
    private var alive = 0
    private var current: String?
    private var errorCount = 0
    private var heaps: [TopFileHeap] = []
    /// File có nhiều hard link chỉ được tính dung lượng một lần.
    private let seenLinks = OSAllocatedUnfairLock(initialState: Set<UInt64>())

    public init(path: String) {
        let full = FileOps.resolvedPath(path)
        root = DirNode(name: full, parent: nil, modified: FileOps.modificationTime(full) ?? 0)
    }

    /// Số thư mục không đọc được.
    public var errors: Int {
        cond.lock(); defer { cond.unlock() }
        return errorCount
    }

    public var currentPath: String? {
        cond.lock(); defer { cond.unlock() }
        return current
    }

    public var isCancelled: Bool {
        cond.lock(); defer { cond.unlock() }
        return cancelled
    }

    /// Quét toàn bộ cây; trả về khi xong hoặc khi bị hủy.
    public func run() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            start { done.resume() }
        }
    }

    public func cancel() {
        cond.lock()
        cancelled = true
        finished = true
        stack.removeAll()
        cond.broadcast()
        cond.unlock()
    }

    /// Các file lớn nhất (tối đa `topFileCapacity`), lớn trước. Gọi sau khi `run()` kết thúc.
    public func topFiles() -> [FileRecord] {
        cond.lock(); defer { cond.unlock() }
        var all = heaps.flatMap(\.items)
        all.sort { $0.size > $1.size }
        return Array(all.prefix(Self.topFileCapacity))
    }

    private func start(_ completion: @escaping @Sendable () -> Void) {
        let workers = max(4, min(16, ProcessInfo.processInfo.activeProcessorCount))
        cond.lock()
        stack = [(root, root.name)]
        pending = 1
        alive = workers
        heaps = (0..<workers).map { _ in TopFileHeap(capacity: Self.topFileCapacity) }
        let heaps = self.heaps
        cond.unlock()

        for i in 0..<workers {
            let heap = heaps[i]
            let thread = Thread { [self] in
                worker(heap)
                cond.lock()
                alive -= 1
                let last = alive == 0
                cond.unlock()
                if last { completion() }
            }
            thread.name = "Scanner\(i)"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    private func worker(_ heap: TopFileHeap) {
        let lister = DirLister()
        while true {
            cond.lock()
            while stack.isEmpty && !finished { cond.wait() }
            if finished {
                cond.unlock()
                return
            }
            let (node, path) = stack.removeLast()
            cond.unlock()

            let subdirs = process(node, path, lister, heap)

            cond.lock()
            if !cancelled && !subdirs.isEmpty {
                // Đẩy ngược để thư mục đầu tiên được lấy ra trước (duyệt theo chiều sâu)
                stack.append(contentsOf: subdirs.reversed())
                pending += subdirs.count
                cond.broadcast()
            }
            pending -= 1
            if pending == 0 {
                finished = true
                cond.broadcast()
            }
            cond.unlock()
        }
    }

    /// Quét một thư mục; trả về các thư mục con cần quét tiếp.
    private func process(_ node: DirNode, _ path: String, _ lister: DirLister, _ heap: TopFileHeap) -> [(node: DirNode, path: String)] {
        cond.lock()
        current = path
        let stop = cancelled
        cond.unlock()
        if stop { return [] }

        var bytes: Int64 = 0
        var files = 0
        var dirs: [DirNode] = []
        var threshold = heap.threshold
        let isVolumeRoot = path == "/"

        let rc = lister.list(path) { e in
            if e.isDirectory {
                let name = e.name
                if isVolumeRoot && DiskScanner.virtualRootDirs.contains(name) { return }
                dirs.append(DirNode(name: name, parent: node, modified: e.modified, isMount: e.isMountPoint))
                return
            }
            var size = e.allocatedSize
            if e.linkCount > 1 && e.isRegularFile && !firstSighting(of: e.fileID) {
                size = 0
            }
            bytes += size
            files += 1
            // Chỉ tạo chuỗi tên cho file đủ lớn để lọt vào danh sách "file lớn nhất"
            if size > 0 && size >= threshold {
                heap.offer(FileRecord(path: isVolumeRoot ? "/" + e.name : path + "/" + e.name,
                                      size: size, modified: e.modified))
                threshold = heap.threshold
            }
        }

        let denied = rc != 0
        if denied {
            cond.lock()
            errorCount += 1
            cond.unlock()
        }
        node.publishScan(ownSize: bytes, ownFiles: files, children: dirs, denied: denied)
        return dirs.filter { !$0.isMount }.map { ($0, FileOps.join(path, $0.name)) }
    }

    private func firstSighting(of fileID: UInt64) -> Bool {
        seenLinks.withLockUnchecked { $0.insert(fileID).inserted }
    }
}

/// Min-heap giữ N file lớn nhất mà một luồng quét đã gặp (mỗi luồng một heap, gộp khi kết thúc).
final class TopFileHeap {
    let capacity: Int
    private(set) var items: [FileRecord] = []

    init(capacity: Int) {
        self.capacity = capacity
        items.reserveCapacity(capacity)
    }

    /// File nhỏ hơn ngưỡng này không thể lọt vào danh sách.
    var threshold: Int64 { items.count < capacity ? 0 : items[0].size + 1 }

    func offer(_ record: FileRecord) {
        if items.count < capacity {
            items.append(record)
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if items[parent].size <= items[i].size { break }
                items.swapAt(parent, i)
                i = parent
            }
        } else if record.size > items[0].size {
            items[0] = record
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var smallest = i
                if l < items.count && items[l].size < items[smallest].size { smallest = l }
                if r < items.count && items[r].size < items[smallest].size { smallest = r }
                if smallest == i { break }
                items.swapAt(i, smallest)
                i = smallest
            }
        }
    }
}
