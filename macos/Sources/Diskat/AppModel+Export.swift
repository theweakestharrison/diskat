import AppKit
import UniformTypeIdentifiers
import DiskatCore

/// Xuất kết quả quét: báo cáo PDF, danh sách thư mục và file dạng CSV; chạy từ dòng lệnh
/// (tương ứng MainWindow.Export.cs của bản Windows).
extension AppModel {
    var canExport: Bool { root != nil && scanner != nil && !isBusy && !isScanning }

    private func defaultExportName(_ ext: String) -> String {
        let path = root?.fullPath ?? "/"
        var name = path == "/" ? "root" : (path as NSString).lastPathComponent
        name = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return "Diskat-\(name)-\(f.string(from: Date())).\(ext)"
    }

    private func askSavePath(title: String, type: UTType, ext: String) -> String? {
        let panel = NSSavePanel()
        panel.title = title
        panel.message = title
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportName(ext)
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// Chạy việc xuất file với lớp phủ "đang xử lý"; mở file khi xong (trừ khi chạy từ dòng lệnh).
    private func runExport(_ busy: String, path: String, open: Bool, background: Bool,
                           work: @escaping @Sendable () throws -> Void, mainWork: (() throws -> Void)? = nil) async -> Bool {
        isBusy = true
        busyText = busy
        defer {
            busyText = nil
            isBusy = false
        }
        // Cho lớp phủ kịp hiện trước khi bắt đầu
        try? await Task.sleep(for: .milliseconds(30))
        do {
            if let mainWork { try mainWork() }
            if background { try await Task.detached(priority: .userInitiated) { try work() }.value }
            setStatus { Loc.f("ExportSaved", path) }
            if open { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            return true
        } catch {
            if open {
                busyText = nil
                await Dialogs.alert(Loc.f("ExportFailed", error.localizedDescription), style: .critical)
            } else {
                let message = error.localizedDescription
                setStatus { Loc.f("ExportFailed", message) }
                FileHandle.standardError.write(Data((Loc.f("ExportFailed", message) + "\n").utf8))
            }
            return false
        }
    }

    // ================= PDF =================

    @discardableResult
    func exportPdf(to target: String? = nil) async -> Bool {
        guard canExport else { return false }
        guard let path = target ?? askSavePath(title: Loc.t("PdfSaveTitle"), type: .pdf, ext: "pdf") else { return false }
        return await runExport(Loc.t("PdfCreating"), path: path, open: target == nil, background: false, work: {}) {
            try PdfReport.write(self.collectReportData(), to: path)
        }
    }

    private func collectReportData() -> ReportData {
        let root = root!
        let sc = scanner!
        var folders = root.children.filter { $0.size > 0 }.map { c in
            ReportFolder(name: c.name, size: c.size, files: c.fileCount, blocked: c.isAccessDenied, isOwnFiles: false,
                         change: comparisonChange(c), isNew: comparisonIsNew(c))
        }
        if root.ownSize > 0 {
            folders.append(ReportFolder(name: "", size: root.ownSize, files: Int64(root.ownFiles), blocked: false, isOwnFiles: true))
        }
        folders = Array(folders.sorted { $0.size > $1.size }.prefix(15))

        let files = topFiles.prefix(25).map { ReportFile(name: $0.name, folder: $0.folder, size: $0.size, modified: $0.modified) }

        var volumeName: String?
        var volumeTotal: Int64 = 0, volumeFree: Int64 = 0
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        if let v = try? URL(fileURLWithPath: root.fullPath).resourceValues(forKeys: keys), let total = v.volumeTotalCapacity {
            volumeName = v.volumeLocalizedName
            volumeTotal = Int64(total)
            let important = v.volumeAvailableCapacityForImportantUsage ?? 0
            volumeFree = important > 0 ? important : Int64(v.volumeAvailableCapacity ?? 0)
        }

        let mapFiles = map?.root === root ? map?.loadedFiles : nil
        return ReportData(
            rootPath: root.fullPath, scannedAt: sc.startedAt, scanSeconds: scanSeconds, scanStopped: scanStopped,
            totalSize: root.size, files: root.fileCount, folders: root.dirCount, blocked: sc.errors, statsStale: statsStale,
            volumeName: volumeName, volumeTotal: volumeTotal, volumeFree: volumeFree,
            treemap: PdfReport.renderTreemap(root: root, files: mapFiles ?? TreemapRenderer.loadFiles(root.fullPath)),
            topFolders: folders, topFiles: Array(files), types: fileTypes, ages: ageStats,
            version: Updater.currentVersion, compare: compareSummary)
    }

    // ================= CSV =================

    /// Excel đọc CSV theo dấu phân cách danh sách của máy (";" ở các nước dùng dấu phẩy thập phân),
    /// nên dùng đúng dấu đó và ghi UTF-8 có BOM để tên tiếng Việt / CJK hiển thị đúng.
    private final class CsvWriter {
        private let handle: FileHandle
        private let sep: String
        private let decimal: String
        private var buffer = Data()
        private static let dateFormat: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f
        }()

        init(_ path: String) throws {
            guard FileManager.default.createFile(atPath: path, contents: Data([0xEF, 0xBB, 0xBF])) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: path])
            }
            handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            handle.seekToEndOfFile()
            decimal = Locale.current.decimalSeparator ?? "."
            sep = decimal == "," ? ";" : ","
        }

        enum Cell {
            case text(String), int(Int64), number(Double), date(Double)
        }

        func row(_ cells: [Cell]) throws {
            let line = cells.map(render).joined(separator: sep) + "\r\n"
            buffer.append(Data(line.utf8))
            if buffer.count > 1 << 16 { try flush() }
        }

        private func render(_ c: Cell) -> String {
            switch c {
            case .int(let n): return String(n)
            case .number(let d): return quote(String(format: "%.2f", d).replacingOccurrences(of: ".", with: decimal))
            case .date(let t): return t > 315_532_800 ? Self.dateFormat.string(from: Date(timeIntervalSince1970: t)) : ""
            case .text(let s): return quote(s)
            }
        }

        private func quote(_ input: String) -> String {
            var s = input
            // Ô bắt đầu bằng = + - @ bị Excel hiểu là công thức: thêm dấu nháy để luôn là chữ
            if let first = s.first, "=+-@".contains(first), Double(s.replacingOccurrences(of: decimal, with: ".")) == nil {
                s = "'" + s
            }
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }

        func flush() throws {
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }

        func close() throws {
            try flush()
            try handle.close()
        }
    }

    @discardableResult
    func exportFoldersCsv(to target: String? = nil) async -> Bool {
        guard canExport, let root else { return false }
        guard let path = target ?? askSavePath(title: Loc.t("CsvFoldersTitle"), type: .commaSeparatedText, ext: "csv") else { return false }
        let header = ["CsvPath", "CsvSizeBytes", "CsvSize", "CsvFiles", "CsvFolders", "CsvPercentParent", "CsvModified",
                      "CsvLevel", "CsvNote"].map(Loc.t)
        let mountNote = Loc.t("CsvMount"), blockedNote = Loc.t("CsvBlocked")
        return await runExport(Loc.t("CsvCreating"), path: path, open: target == nil, background: true, work: {
            let csv = try CsvWriter(path)
            try csv.row(header.map { .text($0) })
            // Duyệt theo chiều sâu, thư mục lớn trước: giống thứ tự trên cây
            var stack: [(DirNode, Int, String)] = [(root, 0, root.fullPath)]
            while let (n, level, nodePath) = stack.popLast() {
                let size = n.size
                let parent = n.parent?.size ?? size
                let p = parent > 0 ? Double(size) * 100 / Double(parent) : 100
                let note = n.isMount ? mountNote : n.isAccessDenied ? blockedNote : ""
                try csv.row([.text(nodePath), .int(size), .text(FileOps.formatSize(size)), .int(n.fileCount), .int(n.dirCount),
                             .number(p), .date(n.modified), .int(Int64(level)), .text(note)])
                for c in n.children.sorted(by: { $0.size < $1.size }) {
                    stack.append((c, level + 1, FileOps.join(nodePath, c.name)))
                }
            }
            try csv.close()
        })
    }

    @discardableResult
    func exportFilesCsv(_ files: [TopFile], to target: String? = nil) async -> Bool {
        guard canExport, !files.isEmpty else { return false }
        guard let path = target ?? askSavePath(title: Loc.t("CsvFilesTitle"), type: .commaSeparatedText, ext: "csv") else { return false }
        let header = ["CsvPath", "CsvName", "CsvFolder", "CsvSizeBytes", "CsvSize", "CsvModified"].map(Loc.t)
        return await runExport(Loc.t("CsvCreating"), path: path, open: target == nil, background: true, work: {
            let csv = try CsvWriter(path)
            try csv.row(header.map { .text($0) })
            for f in files {
                try csv.row([.text(f.path), .text(f.name), .text(f.folder), .int(f.size), .text(FileOps.formatSize(f.size)),
                             .date(f.modified)])
            }
            try csv.close()
        })
    }

    // ================= Dòng lệnh =================

    /// Quét thư mục từ dòng lệnh, ghi các file xuất được yêu cầu, rồi thoát nếu có --quit.
    /// Mã thoát 1 khi có file xuất bị lỗi, để script gọi Diskat biết.
    func runCommandLine(_ options: LaunchOptions) async {
        guard let scanPath = options.scanPath else { return }
        await startScanAsync(scanPath)
        // Không quét được (đường dẫn sai) hoặc người dùng đã quét chỗ khác
        guard let root, root.fullPath == FileOps.resolvedPath(scanPath), !isScanning else {
            if options.quit { exit(1) }
            return
        }
        if options.compare { await compareWithPrevious() }
        var ok = true
        if let p = options.pdfPath { ok = await exportPdf(to: p) && ok }
        if let p = options.foldersCsvPath { ok = await exportFoldersCsv(to: p) && ok }
        if let p = options.filesCsvPath { ok = await exportFilesCsv(topFiles, to: p) && ok }
        if options.quit {
            // Đợi lưu xong lần quét này, để lần chạy sau (vd. báo cáo hằng tuần với --compare) có cái để so
            await waitForSnapshot()
            exit(ok ? 0 : 1)
        }
    }
}
