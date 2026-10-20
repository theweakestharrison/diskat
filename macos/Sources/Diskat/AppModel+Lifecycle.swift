import AppKit
import DiskatCore

/// Các điểm nối giữa luồng quét / xóa và các tính năng khác (so sánh, trùng lặp).
extension AppModel {
    /// Bắt đầu quét thư mục mới.
    func resetForNewScan(_ newRoot: String) {
        suspendComparison(newRoot: newRoot)
        duplicates.reset()
    }

    /// Quét xong (hoặc bị dừng).
    func scanFinishedHooks(cancelled: Bool) {
        scanFinishedCompare(cancelled: cancelled)
    }

    /// path (file hoặc thư mục) vừa bị xóa ở bất kỳ đâu trong app.
    func pathsRemoved(under path: String) {
        duplicates.removeWhere { FileOps.isPath($0, inside: path) }
    }

    /// Vừa quét lại thư mục path: các file trong đó có thể đã biến mất.
    func pathsPruned(under path: String) {
        duplicates.removeWhere { FileOps.isPath($0, inside: path) && !FileOps.exists($0) }
    }
}

