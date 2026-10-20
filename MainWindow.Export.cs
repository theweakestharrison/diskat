using System.Globalization;
using System.Text;
using System.Windows;
using Diskat.Core;
using Diskat.UI;
using Microsoft.Win32;

namespace Diskat;

/// <summary>Xuất kết quả quét: báo cáo PDF, danh sách thư mục và file dạng CSV.</summary>
public partial class MainWindow
{
    // Sau khi xóa / quét lại một phần, thống kê loại file và tuổi file (tính lúc quét) có thể lệch
    private bool _statsStale;
    private bool _scanStopped;

    private bool CanExport => _root != null && _scanner != null && !IsBusy;

    private string DefaultExportName(string ext)
    {
        var root = _root!.FullPath;
        string name = root.Length <= 3 ? root[..1] : Path.GetFileName(root.TrimEnd('\\'));
        foreach (var c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
        return $"Diskat-{name}-{DateTime.Now:yyyyMMdd-HHmm}{ext}";
    }

    private string? AskSavePath(string title, string filter, string ext)
    {
        var dlg = new SaveFileDialog
        {
            Title = title,
            Filter = filter,
            DefaultExt = ext,
            AddExtension = true,
            OverwritePrompt = true,
            FileName = DefaultExportName(ext),
            InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
        };
        return dlg.ShowDialog(this) == true ? dlg.FileName : null;
    }

    /// <summary>Chạy việc xuất file với lớp phủ "đang xử lý"; mở file khi xong.</summary>
    private async Task<bool> RunExportAsync(string busyText, string path, Action work, bool open = true)
    {
        SetBusy(true);
        BusyText.Text = busyText;
        BusyOverlay.Visibility = Visibility.Visible;
        try
        {
            await RunStaAsync(work);
            SetStatus(() => Loc.F("ExportSaved", path));
            if (open) FileOps.OpenWithShell(path);
            return true;
        }
        catch (Exception ex)
        {
            // Chạy từ dòng lệnh (open = false): không hiện hộp thoại chặn
            if (open) MessageBox.Show(this, Loc.F("ExportFailed", ex.Message), "Diskat", MessageBoxButton.OK, MessageBoxImage.Error);
            else SetStatus(() => Loc.F("ExportFailed", ex.Message));
            return false;
        }
        finally
        {
            BusyOverlay.Visibility = Visibility.Collapsed;
            SetBusy(false);
        }
    }

    /// <summary>Luồng STA riêng: PDFsharp bản WPF đọc font qua WPF, an toàn nhất khi chạy trên STA.</summary>
    private static Task RunStaAsync(Action work)
    {
        var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var t = new Thread(() =>
        {
            try { work(); tcs.SetResult(); }
            catch (Exception ex) { tcs.SetException(ex); }
        }) { IsBackground = true, Name = "Export" };
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        return tcs.Task;
    }

    // ================= PDF =================

    private async Task<bool> ExportPdfAsync(string? target = null)
    {
        if (!CanExport) return false;
        var path = target ?? AskSavePath(Loc.T("PdfSaveTitle"), "PDF (*.pdf)|*.pdf", ".pdf");
        if (path == null) return false;

        ReportData data;
        try { data = CollectReportData(); }
        catch (Exception ex)
        {
            MessageBox.Show(this, Loc.F("ExportFailed", ex.Message), "Diskat", MessageBoxButton.OK, MessageBoxImage.Error);
            return false;
        }
        return await RunExportAsync(Loc.T("PdfCreating"), path, () => PdfReport.Save(data, path), open: target == null);
    }

    /// <summary>Quét thư mục từ dòng lệnh, ghi các file xuất được yêu cầu, rồi đóng nếu có --quit.</summary>
    private async Task RunCommandLineAsync(CommandLine cli)
    {
        await StartScanAsync(cli.ScanPath!);
        if (_root == null || !string.Equals(_root.FullPath.TrimEnd('\\'), Path.GetFullPath(cli.ScanPath!).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
            return; // không quét được (đường dẫn sai) hoặc người dùng đã quét chỗ khác
        bool ok = true;
        if (cli.PdfPath != null) ok &= await ExportPdfAsync(cli.PdfPath);
        if (cli.FoldersCsvPath != null) ok &= await ExportFoldersCsvAsync(cli.FoldersCsvPath);
        if (cli.FilesCsvPath != null)
            ok &= await ExportFilesCsvAsync((TopFiles.ItemsSource as IEnumerable<TopFileVM>)?.ToList() ?? [], Loc.T("CsvFilesTitle"), cli.FilesCsvPath);
        // Mã thoát 1 khi có file xuất bị lỗi, để script gọi Diskat biết
        if (cli.Quit) Application.Current.Shutdown(ok ? 0 : 1);
    }

    private ReportData CollectReportData()
    {
        var root = _root!;
        var sc = _scanner!;

        var folders = root.Children
            .Where(c => Interlocked.Read(ref c.Size) > 0)
            .Select(c => new ReportFolder(c.Name, c.Size, c.FileCount, c.AccessDenied || c.BadName, false))
            .ToList();
        if (root.OwnSize > 0) folders.Add(new ReportFolder("", root.OwnSize, root.OwnFiles, false, true));
        folders = folders.OrderByDescending(f => f.Size).Take(15).ToList();

        var files = (_topList ?? [])
            .Take(25)
            .Select(f => new ReportFile(f.Name, f.Folder, f.Size, f.LastWriteUtc))
            .ToList();

        string? driveName = null;
        long driveTotal = 0, driveFree = 0;
        try
        {
            var drive = Path.GetPathRoot(root.FullPath);
            if (!string.IsNullOrEmpty(drive) && !drive.StartsWith(@"\\", StringComparison.Ordinal))
            {
                var di = new DriveInfo(drive);
                if (di.IsReady) { driveName = di.Name.TrimEnd('\\'); driveTotal = di.TotalSize; driveFree = di.TotalFreeSpace; }
            }
        }
        catch { }

        return new ReportData(
            RootPath: root.FullPath,
            ScannedLocal: sc.StartedUtc.ToLocalTime(),
            ScanSeconds: _watch.Elapsed.TotalSeconds,
            ScanStopped: _scanStopped,
            TotalSize: Interlocked.Read(ref root.Size),
            Files: Interlocked.Read(ref root.FileCount),
            Folders: Interlocked.Read(ref root.DirCount),
            Blocked: sc.Errors,
            StatsStale: _statsStale,
            DriveName: driveName,
            DriveTotal: driveTotal,
            DriveFree: driveFree,
            Treemap: PdfReport.RenderTreemap(root, 760, 440),
            Logo: PdfReport.RenderLogo(),
            TopFolders: folders,
            TopFiles: files,
            Types: sc.GetFileTypes(),
            Ages: sc.GetAgeBuckets(),
            Version: Updater.CurrentVersion.ToString());
    }

    // ================= CSV =================

    /// <summary>
    /// Excel đọc CSV theo dấu phân cách danh sách của máy (";" ở nhiều nước dùng dấu phẩy thập phân),
    /// nên dùng đúng dấu đó và ghi UTF-8 có BOM để tên tiếng Việt / CJK hiển thị đúng.
    /// </summary>
    private sealed class CsvWriter(string path) : IDisposable
    {
        private readonly StreamWriter _w = new(path, false, new UTF8Encoding(true));
        private readonly string _sep = CultureInfo.CurrentCulture.TextInfo.ListSeparator is { Length: > 0 } s ? s : ",";

        public void Row(params object?[] cells)
        {
            for (int i = 0; i < cells.Length; i++)
            {
                if (i > 0) _w.Write(_sep);
                _w.Write(Cell(cells[i]));
            }
            _w.Write("\r\n");
        }

        private static string Cell(object? v) => v switch
        {
            null => "",
            long or int => Convert.ToString(v, CultureInfo.InvariantCulture)!,
            double d => Quote(d.ToString("0.##", CultureInfo.CurrentCulture)),
            DateTime t => t.Year < 1980 ? "" : t.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture),
            _ => Quote(v.ToString()!),
        };

        private static string Quote(string s)
        {
            // Ô bắt đầu bằng = + - @ bị Excel hiểu là công thức: thêm dấu nháy để luôn là chữ
            if (s.Length > 0 && s[0] is '=' or '+' or '-' or '@' && !double.TryParse(s, NumberStyles.Float, CultureInfo.CurrentCulture, out _))
                s = "'" + s;
            return "\"" + s.Replace("\"", "\"\"") + "\"";
        }

        public void Dispose() => _w.Dispose();
    }

    private async Task<bool> ExportFoldersCsvAsync(string? target = null)
    {
        if (!CanExport) return false;
        var path = target ?? AskSavePath(Loc.T("CsvFoldersTitle"), "CSV (*.csv)|*.csv", ".csv");
        if (path == null) return false;
        var root = _root!;

        return await RunExportAsync(Loc.T("CsvCreating"), path, () =>
        {
            using var csv = new CsvWriter(path);
            csv.Row(Loc.T("CsvPath"), Loc.T("CsvSizeBytes"), Loc.T("CsvSize"), Loc.T("CsvFiles"), Loc.T("CsvFolders"),
                Loc.T("CsvPercentParent"), Loc.T("CsvModified"), Loc.T("CsvLevel"), Loc.T("CsvNote"));

            // Duyệt theo chiều sâu, thư mục lớn trước: giống thứ tự trên cây
            var stack = new Stack<(DirNode Node, int Level)>();
            stack.Push((root, 0));
            while (stack.Count > 0)
            {
                var (n, level) = stack.Pop();
                long parent = n.Parent?.Size ?? n.Size;
                double pct = parent > 0 ? n.Size * 100.0 / parent : 100;
                string note = n.IsLink ? Loc.T("CsvLink") : n.AccessDenied || n.BadName ? Loc.T("CsvBlocked") : "";
                csv.Row(n.FullPath, n.Size, FileOps.FormatSize(n.Size), n.FileCount, n.DirCount, Math.Round(pct, 2), n.LastWriteUtc.ToLocalTime(), level, note);
                foreach (var c in n.Children.OrderBy(c => c.Size)) stack.Push((c, level + 1));
            }
        }, open: target == null);
    }

    private async Task<bool> ExportFilesCsvAsync(IReadOnlyList<TopFileVM> files, string title, string? target = null)
    {
        if (!CanExport || files.Count == 0) return false;
        var path = target ?? AskSavePath(title, "CSV (*.csv)|*.csv", ".csv");
        if (path == null) return false;
        var snapshot = files.ToList();

        return await RunExportAsync(Loc.T("CsvCreating"), path, () =>
        {
            using var csv = new CsvWriter(path);
            csv.Row(Loc.T("CsvPath"), Loc.T("CsvName"), Loc.T("CsvFolder"), Loc.T("CsvSizeBytes"), Loc.T("CsvSize"), Loc.T("CsvModified"));
            foreach (var f in snapshot)
                csv.Row(f.Path, f.Name, f.Folder, f.Size, FileOps.FormatSize(f.Size), f.LastWriteUtc.ToLocalTime());
        }, open: target == null);
    }
}
