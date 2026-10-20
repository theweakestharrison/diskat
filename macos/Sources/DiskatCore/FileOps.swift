import Foundation

public struct FileItem: Sendable, Hashable {
    public let name: String
    public let size: Int64
    public let modified: Double
}

public enum FileOps {
    // Finder dùng đơn vị thập phân (1 KB = 1000 byte) từ Mac OS X 10.6; dùng giống để số liệu khớp với Finder
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func formatSize(_ bytes: Int64) -> String {
        if bytes < 1000 { return "\(bytes) B" }
        var v = Double(bytes)
        var u = 0
        while v >= 1000 && u < units.count - 1 { v /= 1000; u += 1 }
        let digits = v >= 100 ? 0 : v >= 10 ? 1 : 2
        return String(format: "%.\(digits)f", v) + " " + units[u]
    }

    /// 1234567 -> "1,234,567" (không phụ thuộc ngôn ngữ, giống bản Windows)
    public static func formatCount(_ n: Int64) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    public static func formatCount(_ n: Int) -> String { formatCount(Int64(n)) }

    private static var dateFormatters: [String: DateFormatter] = [:]
    private static let dateLock = NSLock()

    /// Định dạng ngày theo mẫu của ngôn ngữ hiện tại (khóa "DateFormat"); chuỗi rỗng nếu không có ngày.
    public static func formatDate(_ seconds: Double) -> String {
        // Trước 1980: thường là thời gian không hợp lệ
        guard seconds > 315_532_800 else { return "" }
        let pattern = Loc.t("DateFormat")
        dateLock.lock(); defer { dateLock.unlock() }
        let f: DateFormatter
        if let cached = dateFormatters[pattern] {
            f = cached
        } else {
            f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = pattern
            dateFormatters[pattern] = f
        }
        return f.string(from: Date(timeIntervalSince1970: seconds))
    }

    // ---------------- Đường dẫn ----------------

    /// Đường dẫn tuyệt đối thật (giải quyết ~, "..", symlink); giữ nguyên nếu không giải quyết được.
    public static func resolvedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
        if let real = realPath(absolute) { return real }
        let std = URL(fileURLWithPath: absolute).standardized.path
        return std.isEmpty ? "/" : std
    }

    static func realPath(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

    public static func join(_ dir: String, _ name: String) -> String {
        dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }

    /// True nếu `path` là `dir` hoặc nằm bên trong `dir`.
    public static func isPath(_ path: String, inside dir: String) -> Bool {
        path == dir || path.hasPrefix(dir.hasSuffix("/") ? dir : dir + "/")
    }

    /// Có tồn tại không (không đi theo symlink: một symlink hỏng vẫn tính là tồn tại).
    public static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    public static func isDirectory(_ path: String) -> Bool {
        var st = stat()
        return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    public static func modificationTime(_ path: String) -> Double? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
    }

    /// Liệt kê các file nằm trực tiếp trong thư mục (không đệ quy), cùng cách tính dung lượng với bộ quét.
    public static func listFiles(_ dir: String) -> [FileItem] {
        var result: [FileItem] = []
        DirLister().list(dir) { e in
            if !e.isDirectory {
                result.append(FileItem(name: e.name, size: e.allocatedSize, modified: e.modified))
            }
        }
        return result
    }

    // ---------------- An toàn ----------------

    /// Thư mục hệ thống: chặn xóa chính nó và mọi thứ bên trong.
    private static let systemTrees = [
        "/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec", "/usr/share",
        "/usr/standalone", "/private/etc", "/private/var/db", "/private/var/vm", "/Library/Apple",
    ]

    /// Thư mục quan trọng: chặn xóa chính nó hoặc thư mục chứa nó (nội dung bên trong vẫn xóa được).
    private static func criticalFolders() -> [String] {
        var list = [
            "/Applications", "/Library", "/Library/Application Support", "/Users", "/Volumes", "/private",
            "/private/var", "/private/tmp", "/private/var/folders", "/private/var/tmp", "/usr", "/usr/local",
            "/opt", "/etc", "/var", "/tmp", "/cores", "/System/Volumes/Data",
        ]
        let home = resolvedPath(NSHomeDirectory())
        list.append(home)
        for sub in ["Library", "Library/Application Support", "Library/Caches", "Library/Containers",
                    "Library/Group Containers", "Library/Preferences", "Library/Mobile Documents",
                    "Library/CloudStorage", "Desktop", "Documents", "Downloads", "Movies", "Music",
                    "Pictures", "Public", ".Trash"] {
            list.append(home + "/" + sub)
        }
        return list
    }

    /// Trả về lý do nếu đường dẫn không được phép xóa, ngược lại nil.
    public static func protectionReason(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return Loc.t("ProtInvalid") }
        let std = URL(fileURLWithPath: path).standardized.path
        if let reason = checkProtected(std) { return reason }

        // Kiểm tra cả đường dẫn thật (qua symlink ở thư mục cha, ví dụ /tmp -> /private/tmp,
        // /Volumes/Macintosh HD -> /). Mục cuối cùng không bị giải quyết: xóa một symlink chỉ xóa chính nó.
        let parent = (std as NSString).deletingLastPathComponent
        if std != "/", let realParent = realPath(parent) {
            let real = join(realParent, (std as NSString).lastPathComponent)
            if real != std { return checkProtected(real) }
        }
        return nil
    }

    private static let dataVolume = "/System/Volumes/Data"

    private static func checkProtected(_ input: String) -> String? {
        var path = input
        // Ổ dữ liệu được nối vào "/" qua firmlink: /System/Volumes/Data/Users/x chính là /Users/x
        if path.hasPrefix(dataVolume + "/") { path = String(path.dropFirst(dataVolume.count)) }

        if path == "/" || isVolumeRoot(input) { return Loc.t("ProtDrive") }

        for dir in systemTrees where isPath(path, inside: dir) {
            return Loc.t("ProtMacSystem")
        }

        for c in criticalFolders() where isPath(c, inside: path) {
            return Loc.t("ProtSystem")
        }

        // Thư mục gốc của bất kỳ tài khoản người dùng nào (/Users/<tên>)
        if (path as NSString).deletingLastPathComponent == "/Users" { return Loc.t("ProtProfile") }
        return nil
    }

    /// True nếu đường dẫn là điểm gắn của một ổ (ổ ngoài, ổ mạng, ảnh đĩa...).
    static func isVolumeRoot(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return false }
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return false }
        let mountPoint = withUnsafePointer(to: &fs.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return mountPoint == path
    }

    // ---------------- Xóa ----------------

    /// Đưa vào Thùng rác (giống lệnh "Chuyển vào Thùng rác" của Finder).
    public static func moveToTrash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }

    public static func deletePermanently(_ path: String) throws {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            // Mở khóa (cờ "Locked" của Finder) và cấp quyền ghi cho thư mục chỉ-đọc (ví dụ bộ đệm module của Go)
            // rồi thử lại. Không đi qua symlink hay sang ổ khác, nên không đụng tới file nằm NGOÀI thư mục cần xóa.
            unlockTree(path)
            try FileManager.default.removeItem(atPath: path)
        }
    }

    private static func unlockTree(_ path: String) {
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        if st.st_flags & UInt32(UF_IMMUTABLE) != 0 { lchflags(path, st.st_flags & ~UInt32(UF_IMMUTABLE)) }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return }
        if st.st_mode & S_IWUSR == 0 { chmod(path, (st.st_mode & 0o7777) | S_IWUSR | S_IXUSR) }

        var subdirs: [String] = []
        let lister = DirLister()
        lister.list(path) { e in
            let child = join(path, e.name)
            if e.isDirectory {
                if !e.isMountPoint { subdirs.append(child) }
            } else {
                var cst = stat()
                if lstat(child, &cst) == 0 && cst.st_flags & UInt32(UF_IMMUTABLE) != 0 {
                    lchflags(child, cst.st_flags & ~UInt32(UF_IMMUTABLE))
                }
            }
        }
        for dir in subdirs { unlockTree(dir) }
    }
}
