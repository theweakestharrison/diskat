using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using Diskat.Core;
using Diskat.UI;

namespace Diskat;

/// <summary>
/// Lịch sử quét: lưu cây thư mục sau mỗi lần quét xong (Core/ScanSnapshot.cs, chỉ trên máy này) và so cây
/// đang hiển thị với một lần quét trước. Khi so sánh, cây có thêm cột "Thay đổi", nhãn "mới" cho thư mục
/// mới, và dòng tóm tắt phía trên.
/// </summary>
public partial class MainWindow
{
    private ScanComparison? _compare;
    // Lần quét đã chọn để so: giữ lại để so tiếp sau khi quét lại đúng thư mục đó
    private SnapshotInfo? _compareWith;
    // Các lần lưu nối tiếp nhau, chạy ở luồng nền
    private Task _snapshotTask = Task.CompletedTask;

    private GridViewColumn ChangeColumn => (GridViewColumn)Resources["ChangeColumn"];

    private static string When(DateTime utc) =>
        utc.ToLocalTime().ToString(Loc.T("DateFormat"), CultureInfo.InvariantCulture);

    private static string Signed(long n) => (n > 0 ? "+" : n < 0 ? "-" : "") + FileOps.FormatCount(Math.Abs(n));

    // ================= Lưu =================

    /// <summary>Gọi khi quét xong trọn vẹn (không bị dừng): lưu lần quét này rồi so tiếp với lần quét đã chọn.</summary>
    private void OnScanFinishedCompare(bool cancelled)
    {
        if (cancelled || _root == null || _scanner == null) return;

        if (Settings.Current.SaveScanHistory)
        {
            var root = _root;
            var scannedUtc = _scanner.StartedUtc;
            int errors = _scanner.Errors;
            string version = Updater.CurrentVersion.ToString();
            // Khoảng 0,3 giây cho 500.000 thư mục, ở luồng nền nên không làm chậm giao diện
            _snapshotTask = _snapshotTask.ContinueWith(_ =>
            {
                try { ScanSnapshot.Save(root, scannedUtc, errors, version); }
                catch { } // ổ đầy, không có quyền ghi...: chỉ mất lần lưu này, kết quả quét không ảnh hưởng
            }, TaskScheduler.Default);
        }

        if (_compareWith is { } info)
        {
            if (File.Exists(info.FilePath)) _ = StartComparisonAsync(info, quiet: true);
            else _compareWith = null;
        }
    }

    // ================= So sánh =================

    private async Task StartComparisonAsync(SnapshotInfo info, bool quiet = false)
    {
        if (_root == null || IsScanning) return;
        var root = _root;
        ScanComparison cmp;
        try { cmp = await Task.Run(() => ScanComparison.Load(info.FilePath, root)); }
        catch (Exception ex)
        {
            if (quiet) _compareWith = null;
            else MessageBox.Show(this, Loc.F("CompareLoadFailed", ex.Message), "Diskat", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        // Trong lúc nạp, người dùng đã bắt đầu quét lại hoặc quét thư mục khác
        if (!ReferenceEquals(root, _root) || IsScanning) return;
        _compare = cmp;
        _compareWith = info;
        ApplyComparison();
    }

    private void StopComparison()
    {
        _compare = null;
        _compareWith = null;
        ApplyComparison();
    }

    private void StopCompare_Click(object sender, RoutedEventArgs e) => StopComparison();

    /// <summary>Bắt đầu quét mới: tắt so sánh trong lúc quét. Quét lại đúng thư mục đang so thì so tiếp khi quét xong.</summary>
    private void SuspendComparison(string newRoot)
    {
        if (_compareWith != null)
        {
            bool same;
            try { same = ScanSnapshot.SameRoot(_compareWith.RootPath, newRoot); } catch { same = false; }
            if (!same) _compareWith = null;
        }
        _compare = null;
        ApplyComparison(rebuild: false);
    }

    /// <summary>--compare: so với lần quét đã lưu gần nhất trước lần này (cho báo cáo PDF từ dòng lệnh).</summary>
    private async Task CompareWithPreviousAsync()
    {
        if (_root == null || _scanner == null) return;
        var current = _scanner.StartedUtc;
        SnapshotInfo? previous;
        try { previous = ScanSnapshot.List(_root.FullPath).FirstOrDefault(s => s.ScannedUtc < current); }
        catch { previous = null; }
        if (previous != null) await StartComparisonAsync(previous, quiet: true);
    }

    /// <summary>Hiện / ẩn cột "Thay đổi" (ngay sau cột Dung lượng) theo trạng thái so sánh, rồi vẽ lại cây.</summary>
    private void ApplyComparison(bool rebuild = true)
    {
        Row.Comparison = _compare;
        if (Tree.View is GridView gv)
        {
            var col = ChangeColumn;
            bool shown = gv.Columns.Contains(col);
            if (_compare != null && !shown)
            {
                // Người dùng có thể đã kéo đổi thứ tự cột: tìm cột Dung lượng theo Tag
                int size = gv.Columns.TakeWhile(c => (c.Header as GridViewColumnHeader)?.Tag as string != "size").Count();
                gv.Columns.Insert(Math.Min(size + 1, gv.Columns.Count), col);
            }
            else if (_compare == null && shown) gv.Columns.Remove(col);
        }
        if (_compare == null && _sortKey == "change")
        {
            _sortKey = _sortHeaderTag = "size";
            _sortDesc = true;
        }
        UpdateHeaderCaptions();
        if (rebuild) RebuildRows();
        else UpdateCompareBar();
    }

    /// <summary>"Tăng 3.2 GB so với lần quét lúc ..." và số file thay đổi: cho thanh tóm tắt và báo cáo PDF.</summary>
    private string? CompareSummary()
    {
        if (_compare is not { } c || !ReferenceEquals(c.Root, _root)) return null;
        long delta = c.SizeChange(c.Root);
        long files = Interlocked.Read(ref c.Root.FileCount) - c.FilesAt(0);
        string when = When(c.Info.ScannedUtc);
        string text = delta > 0 ? Loc.F("CompareGrew", FileOps.FormatSize(delta), when)
                    : delta < 0 ? Loc.F("CompareShrank", FileOps.FormatSize(-delta), when)
                    : Loc.F("CompareSame", when);
        if (files != 0) text += "  ·  " + Loc.F("CompareFiles", Signed(files));
        return text;
    }

    /// <summary>Gọi mỗi khi cây được vẽ lại (sau khi xóa, quét lại một thư mục, đổi ngôn ngữ).</summary>
    private void UpdateCompareBar()
    {
        if (CompareSummary() is not { } text)
        {
            CompareBar.Visibility = Visibility.Collapsed;
            return;
        }
        CompareText.Text = text;
        CompareText.ToolTip = text;
        CompareNote.Text = Loc.T("CompareStopped");
        CompareNote.Visibility = _scanStopped ? Visibility.Visible : Visibility.Collapsed;
        CompareBar.Visibility = Visibility.Visible;
    }

    // ================= Menu ⋯ =================

    /// <summary>Mục "So sánh với lần quét trước": các lần quét đã lưu của thư mục đang xem, mới nhất trước.</summary>
    private MenuItem CompareMenuItem()
    {
        var item = new MenuItem { Header = Loc.T("MenuCompare") };
        if (_root == null || IsBusy)
        {
            item.IsEnabled = false;
            return item;
        }

        List<SnapshotInfo> saved;
        try { saved = ScanSnapshot.List(_root.FullPath); } catch { saved = []; }
        // Lần quét đang hiển thị đã được lưu ngay khi quét xong: so với chính nó thì không có gì để xem
        var current = _scanner?.StartedUtc;
        saved.RemoveAll(s => s.ScannedUtc == current);

        foreach (var s in saved)
        {
            var mi = new MenuItem
            {
                Header = $"{When(s.ScannedUtc)}  ·  {FileOps.FormatSize(s.TotalSize)}",
                IsChecked = _compare != null && string.Equals(_compare.Info.FilePath, s.FilePath, StringComparison.OrdinalIgnoreCase),
            };
            mi.Click += (_, _) => _ = StartComparisonAsync(s);
            item.Items.Add(mi);
        }
        if (saved.Count == 0) item.Items.Add(new MenuItem { Header = Loc.T("MenuCompareNone"), IsEnabled = false });

        if (_compare != null)
        {
            item.Items.Add(new Separator());
            var stop = new MenuItem { Header = Loc.T("CompareStop") };
            stop.Click += (_, _) => StopComparison();
            item.Items.Add(stop);
        }

        item.Items.Add(new Separator());
        var keep = new MenuItem { Header = Loc.T("MenuCompareSave"), IsCheckable = true, IsChecked = Settings.Current.SaveScanHistory };
        keep.Click += (_, _) =>
        {
            Settings.Current.SaveScanHistory = keep.IsChecked;
            Settings.Current.Save();
        };
        item.Items.Add(keep);

        int stored;
        try { stored = ScanSnapshot.Usage().Count; } catch { stored = 0; }
        var clear = new MenuItem { Header = Loc.T("MenuCompareClear"), IsEnabled = stored > 0 };
        clear.Click += (_, _) => _ = DeleteSavedScansAsync();
        item.Items.Add(clear);
        return item;
    }

    private async Task DeleteSavedScansAsync()
    {
        // Đợi lần lưu đang chạy (nếu có) để không còn sót lại file vừa ghi
        await _snapshotTask;
        int count;
        long bytes;
        try { (count, bytes) = ScanSnapshot.Usage(); } catch { return; }
        if (count == 0) return;
        if (MessageBox.Show(this, Loc.F("CompareClearAsk", FileOps.FormatCount(count), FileOps.FormatSize(bytes)), "Diskat",
                MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes)
            return;

        StopComparison();
        int deleted = await Task.Run(ScanSnapshot.DeleteAll);
        SetStatus(() => Loc.F("CompareCleared", FileOps.FormatCount(deleted)));
    }
}
