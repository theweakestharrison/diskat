import Foundation

/// Tổng theo phần mở rộng (".mp4", "" = không có phần mở rộng).
public struct TypeStat: Sendable, Hashable {
    public let ext: String
    public let size: Int64
    public let count: Int64
}

/// Tổng theo tuổi file (lần sửa cuối). maxDays = nil: nhóm cũ nhất.
public struct AgeStat: Sendable, Hashable {
    public let maxDays: Int?
    public let size: Int64
    public let count: Int64
}

/// Thống kê riêng của một luồng quét, gộp lại khi quét xong (không cần khóa trong lúc quét).
final class WorkerStats {
    static let ageLimitsDays = [30, 182, 365, 730, 1825]

    /// Phần mở rộng (tối đa 12 byte kể cả dấu chấm, chữ thường) gói trong 16 byte: không tạo String cho từng file.
    struct ExtKey: Hashable {
        var a: UInt64 = 0
        var b: UInt64 = 0

        var string: String {
            var bytes: [UInt8] = []
            for word in [a, b] {
                for i in 0..<8 {
                    let byte = UInt8((word >> (8 * UInt64(i))) & 0xFF)
                    if byte == 0 { return String(decoding: bytes, as: UTF8.self) }
                    bytes.append(byte)
                }
            }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    final class Total {
        var size: Int64 = 0
        var count: Int64 = 0
    }

    private(set) var types: [ExtKey: Total] = [:]
    private(set) var ageSize = [Int64](repeating: 0, count: ageLimitsDays.count + 1)
    private(set) var ageCount = [Int64](repeating: 0, count: ageLimitsDays.count + 1)
    private let ageLimits: [Double]

    init(now: Date) {
        let t = now.timeIntervalSince1970
        ageLimits = Self.ageLimitsDays.map { t - Double($0) * 86_400 }
    }

    /// Phần mở rộng của tên file (nil nếu không có). Giống bản Windows: tên kiểu "bản sao.2023 cuối",
    /// ".bashrc" hay đuôi dài hơn 12 ký tự không được coi là phần mở rộng.
    static func extensionKey(_ name: UnsafePointer<CChar>) -> ExtKey? {
        let len = strlen(name)
        var dot = len - 1
        while dot > 0 && name[dot] != 0x2E { dot -= 1 } // '.'
        guard dot > 0, len - dot >= 2, len - dot <= 12 else { return nil }
        var key = ExtKey()
        for i in dot..<len {
            var c = UInt8(bitPattern: name[i])
            if c == 0x20 { return nil } // khoảng trắng
            if c >= 0x41 && c <= 0x5A { c += 0x20 } // A-Z -> a-z
            let j = i - dot
            if j < 8 { key.a |= UInt64(c) << (8 * UInt64(j)) } else { key.b |= UInt64(c) << (8 * UInt64(j - 8)) }
        }
        return key
    }

    private static let noExtension = ExtKey()

    func add(name: UnsafePointer<CChar>, size: Int64, modified: Double) {
        let key = Self.extensionKey(name) ?? Self.noExtension
        let total: Total
        if let t = types[key] {
            total = t
        } else {
            total = Total()
            types[key] = total
        }
        total.size += size
        total.count += 1

        var bucket = 0
        while bucket < ageLimits.count && modified < ageLimits[bucket] { bucket += 1 }
        ageSize[bucket] += size
        ageCount[bucket] += 1
    }

    /// Gộp thống kê của các luồng: loại file lớn nhất trước.
    static func mergeTypes(_ all: [WorkerStats]) -> [TypeStat] {
        var merged: [ExtKey: (size: Int64, count: Int64)] = [:]
        for s in all {
            for (k, t) in s.types {
                let cur = merged[k] ?? (0, 0)
                merged[k] = (cur.size + t.size, cur.count + t.count)
            }
        }
        return merged.map { TypeStat(ext: $0.key.string, size: $0.value.size, count: $0.value.count) }
            .sorted { $0.size != $1.size ? $0.size > $1.size : $0.ext < $1.ext }
    }

    /// Gộp theo nhóm tuổi, từ mới đến cũ.
    static func mergeAges(_ all: [WorkerStats]) -> [AgeStat] {
        let n = ageLimitsDays.count + 1
        var size = [Int64](repeating: 0, count: n)
        var count = [Int64](repeating: 0, count: n)
        for s in all {
            for i in 0..<n {
                size[i] += s.ageSize[i]
                count[i] += s.ageCount[i]
            }
        }
        return (0..<n).map { AgeStat(maxDays: $0 < n - 1 ? ageLimitsDays[$0] : nil, size: size[$0], count: count[$0]) }
    }
}
