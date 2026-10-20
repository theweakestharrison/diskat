import CoreGraphics

/// Một ô trên bản đồ dung lượng trước khi được xếp chỗ.
public struct TreemapEntry {
    public var size: Int64
    /// Thư mục (nil nếu là file / nhóm file)
    public var node: DirNode?
    /// File đơn lẻ
    public var filePath: String?
    public var label: String
    public var isGroup: Bool

    public init(size: Int64, node: DirNode? = nil, filePath: String? = nil, label: String, isGroup: Bool = false) {
        self.size = size
        self.node = node
        self.filePath = filePath
        self.label = label
        self.isGroup = isGroup
    }
}

public enum TreemapLayout {
    public static let maxItemsPerLevel = 1500

    /// Các ô của một thư mục, lớn trước. `files`: file nằm trực tiếp trong thư mục nếu đã liệt kê
    /// (kèm số lượng / dung lượng phần còn lại); nil thì gộp mọi file thành một ô "[N file]".
    public static func entries(of dir: DirNode, files: (items: [FileItem], restCount: Int, restSize: Int64)?) -> [TreemapEntry] {
        let children = dir.children
        var list: [TreemapEntry] = []
        list.reserveCapacity(children.count + 8)
        for c in children {
            let s = c.size
            if s > 0 { list.append(TreemapEntry(size: s, node: c, label: c.name)) }
        }
        if let files, !files.items.isEmpty {
            let base = dir.fullPath
            for f in files.items where f.size > 0 {
                list.append(TreemapEntry(size: f.size, filePath: FileOps.join(base, f.name), label: f.name))
            }
            if files.restSize > 0 {
                list.append(TreemapEntry(size: files.restSize, label: Loc.f("MapFiles", FileOps.formatCount(files.restCount)), isGroup: true))
            }
        } else {
            let own = dir.ownSize
            if own > 0 {
                list.append(TreemapEntry(size: own, label: Loc.f("MapFiles", FileOps.formatCount(dir.ownFiles)), isGroup: true))
            }
        }

        list.sort { $0.size > $1.size }
        if list.count > maxItemsPerLevel {
            let keep = maxItemsPerLevel - 1
            let rest = list[keep...].reduce(Int64(0)) { $0 + $1.size }
            let restCount = list.count - keep
            list.removeSubrange(keep...)
            list.append(TreemapEntry(size: rest, label: Loc.f("MapOthers", FileOps.formatCount(restCount)), isGroup: true))
        }
        return list
    }

    /// Thuật toán "squarified treemap": xếp các ô (đã sắp giảm dần) vào `rect` sao cho tỉ lệ cạnh gần 1.
    /// Gọi `place(index, rect)` cho từng ô được xếp.
    public static func squarify(_ sizes: [Int64], in rect: CGRect, place: (Int, CGRect) -> Void) {
        let total = sizes.reduce(0.0) { $0 + Double($1) }
        guard total > 0, rect.width >= 1, rect.height >= 1 else { return }

        let scale = Double(rect.width * rect.height) / total
        let n = sizes.count
        var i = 0
        var rx = Double(rect.minX), ry = Double(rect.minY), rw = Double(rect.width), rh = Double(rect.height)

        while i < n {
            let side = min(rw, rh)
            if side <= 0.5 { break }

            var j = i
            var rowSum = 0.0, best = Double.greatestFiniteMagnitude
            let amax = Double(sizes[i]) * scale
            while j < n {
                let a = Double(sizes[j]) * scale
                if a <= 0 { j += 1; continue }
                let s = rowSum + a
                let w2 = side * side, s2 = s * s
                let worst = max(w2 * amax / s2, s2 / (w2 * a))
                if worst > best { break }
                best = worst
                rowSum = s
                j += 1
            }
            if rowSum <= 0 { break }

            let thick = rowSum / side
            if rw >= rh {
                var y = ry
                for k in i..<j {
                    let h = Double(sizes[k]) * scale / thick
                    place(k, CGRect(x: rx, y: y, width: thick, height: h))
                    y += h
                }
                rx += thick
                rw = max(0, rw - thick)
            } else {
                var x = rx
                for k in i..<j {
                    let w = Double(sizes[k]) * scale / thick
                    place(k, CGRect(x: x, y: ry, width: w, height: thick))
                    x += w
                }
                ry += thick
                rh = max(0, rh - thick)
            }
            i = j
        }
    }
}
