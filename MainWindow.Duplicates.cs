using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Diskat.Core;

namespace Diskat;

/// <summary>Dòng tiêu đề của một nhóm file giống hệt nhau.</summary>
public sealed class DupGroupVM : INotifyPropertyChanged
{
    private readonly MainWindow _owner;
    private bool _expanded = true;

    public DupGroupVM(MainWindow owner, DupGroup group)
    {
        _owner = owner;
        Size = group.Size;
        Files = group.Files.Select(f => new DupFileVM(this, f)).ToList();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public bool IsHeader => true;
    public long Size { get; }
    public List<DupFileVM> Files { get; }

    /// <summary>Giải phóng được khi chỉ giữ một bản (bản có hard link xóa đi cũng không được chỗ nào).</summary>
    public long Wasted => Size * Math.Min(Files.Count - 1, Files.Count(f => f.CanCheck));
    public string Name => Files.Count > 0 ? System.IO.Path.GetFileName(Files[0].Path) : "";
    public string Summary => Loc.F("DupGroupCopies", FileOps.FormatCount(Files.Count), FileOps.FormatSize(Size));
    public string WastedText => Loc.F("DupGroupWasted", FileOps.FormatSize(Wasted));
    public string SelectedText => Files.Count(f => f.IsChecked) is var n and > 0 ? Loc.F("DupGroupSelected", FileOps.FormatCount(n)) : "";

    public bool IsExpanded
    {
        get => _expanded;
        set
        {
            if (value == _expanded) return;
            _expanded = value;
            Refresh();
            _owner.OnDupGroupToggled(this);
        }
    }

    /// <summary>Đánh dấu thêm một bản chỉ khi vẫn còn ít nhất một bản khác không bị đánh dấu.</summary>
    internal bool CanCheckAnother => Files.Count(f => !f.IsChecked) > 1;

    internal void OnFileChecked(DupFileVM file, bool value)
    {
        Refresh();
        _owner.OnDupCheckChanged(file, value);
    }

    internal void OnRefused() => _owner.OnDupKeepOne();

    public void Refresh() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));
}

/// <summary>Một bản trong nhóm trùng lặp.</summary>
public sealed class DupFileVM : INotifyPropertyChanged
{
    private bool _checked;

    public DupFileVM(DupGroupVM group, DupFile file)
    {
        Group = group;
        File = file;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public bool IsHeader => false;
    public DupGroupVM Group { get; }
    public DupFile File { get; }
    public string Path => File.Path;
    public string Name => System.IO.Path.GetFileName(Path);
    public string Folder => "   " + (System.IO.Path.GetDirectoryName(Path) ?? "");
    public string Modified => File.LastWriteUtc.Year < 1980 ? "" : File.LastWriteUtc.ToLocalTime().ToString(Loc.T("DateFormat"), CultureInfo.InvariantCulture);
    public bool CanCheck => !File.IsHardLinked;
    public string Note => File.IsHardLinked ? Loc.T("DupHardLink") : "";

    public string Tip
    {
        get
        {
            if (!File.IsHardLinked) return Path;
            string tip = Path + "\n\n" + Loc.F("DupHardLinkTip", FileOps.FormatCount(File.LinkCount));
            if (File.OtherNames.Count > 0) tip += "\n\n" + Loc.T("DupAlsoAt") + "\n" + string.Join("\n", File.OtherNames);
            return tip;
        }
    }

    public bool IsChecked
    {
        get => _checked;
        set
        {
            if (value == _checked) return;
            if (value && (!CanCheck || !Group.CanCheckAnother))
            {
                // Không cho đánh dấu bản cuối cùng của nhóm: trả ô đánh dấu về như cũ sau khi binding cập nhật xong
                Application.Current.Dispatcher.BeginInvoke(() => Notify(nameof(IsChecked)));
                Group.OnRefused();
                return;
            }
            _checked = value;
            Notify(nameof(IsChecked));
            Group.OnFileChecked(this, value);
        }
    }

    /// <summary>Đặt thẳng, không kiểm tra (dùng cho chọn hàng loạt; nơi gọi tự bảo đảm còn một bản giữ lại).</summary>
    internal void SetChecked(bool value)
    {
        if (value == _checked) return;
        _checked = value;
        Notify(nameof(IsChecked));
    }

    public void Refresh() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));
    private void Notify(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>Danh sách phẳng (tiêu đề nhóm + các bản) cho ListView, chèn / xóa hàng loạt bằng một sự kiện Reset.</summary>
public sealed class DupRows : ObservableCollection<object>
{
    private const int BulkThreshold = 40;
    private List<object> Inner => (List<object>)Items;

    public void ReplaceAll(IEnumerable<object> rows)
    {
        Inner.Clear();
        Inner.AddRange(rows);
        RaiseReset();
    }

    public void InsertRange(int index, IList<DupFileVM> rows)
    {
        if (rows.Count <= BulkThreshold) { for (int i = 0; i < rows.Count; i++) Insert(index + i, rows[i]); return; }
        Inner.InsertRange(index, rows);
        RaiseReset();
    }

    public void RemoveRange(int index, int count)
    {
        if (count <= BulkThreshold) { for (int i = 0; i < count; i++) RemoveAt(index); return; }
        Inner.RemoveRange(index, count);
        RaiseReset();
    }

    private void RaiseReset()
    {
        OnPropertyChanged(new PropertyChangedEventArgs(nameof(Count)));
        OnPropertyChanged(new PropertyChangedEventArgs("Item[]"));
        OnCollectionChanged(new NotifyCollectionChangedEventArgs(NotifyCollectionChangedAction.Reset));
    }
}

/// <summary>Tab Trùng lặp: tìm file giống hệt nhau trong thư mục đã quét, đánh dấu các bản thừa rồi xóa an toàn.</summary>
public partial class MainWindow
{
    private readonly DupRows _dupRows = new();
    private List<DupGroupVM>? _dupGroups;
    private DupResult? _dupResult;
    private string _dupMinLabel = "";
    private CancellationTokenSource? _dupCts;
    private long _dupCheckedCount, _dupCheckedBytes;
    // Đang xóa nhiều file: gom việc dựng lại danh sách vào một lần ở cuối
    private bool _dupBatch, _dupDirty;

    private static readonly long[] DupSizes = [100L << 10, 1L << 20, 10L << 20, 100L << 20, 1L << 30];
    private static readonly string[] DupSizeLabels = ["100 KB", "1 MB", "10 MB", "100 MB", "1 GB"];
    private const int DupDefaultSize = 1; // 1 MB

    /// <summary>Gọi một lần sau InitializeComponent.</summary>
    private void InitDuplicates()
    {
        var v = DupView;
        v.List.ItemsSource = _dupRows;
        v.FindBtn.Click += (_, _) =>
        {
            if (_dupCts != null) _dupCts.Cancel();
            else _ = RunDuplicatesAsync();
        };
        v.KeepNewestBtn.Click += (_, _) => DupSelectAllButNewest();
        v.ClearBtn.Click += (_, _) => DupClearChecks();
        v.DeleteBtn.Click += (_, _) => _ = DeleteDuplicatesAsync(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift));
        v.MenuDeletePerm.Click += (_, _) => _ = DeleteDuplicatesAsync(true);
        v.MenuExplorer.Click += (_, _) => { if (DupSelectedFiles().FirstOrDefault() is { } f) FileOps.SelectInExplorer(f.Path); };
        v.MenuOpen.Click += (_, _) => { if (DupSelectedFiles().FirstOrDefault() is { } f) FileOps.OpenWithShell(f.Path); };
        v.MenuCopy.Click += (_, _) =>
        {
            var files = DupSelectedFiles();
            if (files.Count > 0) TrySetClipboard(string.Join(Environment.NewLine, files.Select(f => f.Path)));
        };
        v.List.MouseDoubleClick += DupList_MouseDoubleClick;
        v.List.PreviewKeyDown += DupList_PreviewKeyDown;
    }

    /// <summary>Gọi khi đổi ngôn ngữ.</summary>
    private void InitDupFilters()
    {
        var box = DupView.MinSize;
        int si = box.SelectedIndex < 0 ? DupDefaultSize : box.SelectedIndex;
        box.ItemsSource = DupSizeLabels.Select(l => Loc.F("FindSizeMin", l)).ToList();
        box.SelectedIndex = si;
        FitComboWidth(box, 110);
        DupView.FindBtn.Content = Loc.T(_dupCts != null ? "FindStop" : "DupFind");
        if (_dupGroups != null)
            foreach (var g in _dupGroups)
            {
                g.Refresh();
                foreach (var f in g.Files) f.Refresh();
            }
        UpdateDupInfo();
        UpdateDupSelection();
    }

    /// <summary>Dừng tìm và bỏ kết quả cũ khi bắt đầu quét thư mục mới.</summary>
    private void ResetDuplicates()
    {
        _dupCts?.Cancel();
        _dupCts = null;
        DupView.FindBtn.Content = Loc.T("DupFind");
        DupView.Progress.Visibility = Visibility.Collapsed;
        ClearDupResults();
    }

    private void ClearDupResults()
    {
        _dupGroups = null;
        _dupResult = null;
        _dupRows.ReplaceAll([]);
        _dupCheckedCount = _dupCheckedBytes = 0;
        UpdateDupInfo();
        UpdateDupSelection();
    }

    private void UpdateDupInfo()
    {
        if (_dupCts != null) return; // đang tìm: dòng tiến độ do bộ đếm giờ cập nhật
        var info = DupView.Info;
        if (_root == null) { info.Text = Loc.T("DupEmpty"); return; }
        if (IsScanning) { info.Text = Loc.T("InsightsWait"); return; }
        if (_dupGroups == null || _dupResult == null) { info.Text = Loc.F("DupHint", _root.FullPath); return; }

        string text = _dupGroups.Count == 0
            ? Loc.F("DupNone", _dupMinLabel)
            : Loc.F("DupResult", FileOps.FormatCount(_dupGroups.Count), FileOps.FormatSize(_dupGroups.Sum(g => g.Wasted)));
        if (_dupResult.CloudSkipped > 0) text += " " + Loc.F("DupSkippedCloud", FileOps.FormatCount(_dupResult.CloudSkipped));
        if (_dupResult.Unreadable > 0) text += " " + Loc.F("DupUnreadable", FileOps.FormatCount(_dupResult.Unreadable));
        info.Text = text;
    }

    private void UpdateDupSelection()
    {
        var v = DupView;
        bool any = _dupGroups is { Count: > 0 };
        v.ActionBar.Visibility = any ? Visibility.Visible : Visibility.Collapsed;
        v.SelInfo.Text = _dupCheckedCount == 0
            ? Loc.T("DupSelNone")
            : Loc.F("DupSelInfo", FileOps.FormatCount(_dupCheckedCount), FileOps.FormatSize(_dupCheckedBytes));
        v.DeleteBtn.IsEnabled = _dupCheckedCount > 0;
        v.ClearBtn.IsEnabled = _dupCheckedCount > 0;
        v.KeepNewestBtn.IsEnabled = any;
    }

    // ================= Tìm =================

    private async Task RunDuplicatesAsync()
    {
        if (_dupCts != null || _root == null) return;
        if (IsScanning) { DupView.Info.Text = Loc.T("InsightsWait"); return; }

        int si = Math.Max(0, DupView.MinSize.SelectedIndex);
        long minSize = DupSizes[si];
        bool skipSystem = DupView.SkipSystem.IsChecked == true;
        string root = _root.FullPath;
        var scanRoot = _root;

        ClearDupResults();
        var cts = new CancellationTokenSource();
        _dupCts = cts;
        var v = DupView;
        v.FindBtn.Content = Loc.T("FindStop");
        v.Progress.Visibility = Visibility.Visible;

        var progress = new DuplicateFinder.Progress();
        void Show()
        {
            long done = Volatile.Read(ref progress.Done), total = Volatile.Read(ref progress.Total);
            switch (Volatile.Read(ref progress.Stage))
            {
                case 0:
                    v.Info.Text = Loc.F("DupListing", FileOps.FormatCount(Volatile.Read(ref progress.Found)), root);
                    v.Progress.IsIndeterminate = true;
                    break;
                case 1:
                    v.Info.Text = Loc.F("DupHead", FileOps.FormatCount(done), FileOps.FormatCount(total));
                    v.Progress.IsIndeterminate = false;
                    v.Progress.Value = total > 0 ? (double)done / total : 0;
                    break;
                default:
                    v.Info.Text = Loc.F("DupFull", FileOps.FormatSize(done), FileOps.FormatSize(total));
                    v.Progress.IsIndeterminate = false;
                    v.Progress.Value = total > 0 ? (double)done / total : 1;
                    break;
            }
        }
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        timer.Tick += (_, _) => Show();
        Show();
        timer.Start();
        bool failed = false;
        try
        {
            var result = await Task.Run(() => DuplicateFinder.Find(root, minSize, skipSystem, progress, cts.Token));
            if (!ReferenceEquals(scanRoot, _root) || cts.IsCancellationRequested) return; // đã quét thư mục khác trong lúc tìm
            _dupResult = result;
            _dupMinLabel = DupSizeLabels[si];
            _dupGroups = result.Groups.Select(g => new DupGroupVM(this, g)).ToList();
            RebuildDupRows();
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            failed = true;
            v.Info.Text = Loc.F("FindFailed", ex.Message);
        }
        finally
        {
            timer.Stop();
            if (ReferenceEquals(_dupCts, cts))
            {
                _dupCts = null;
                v.FindBtn.Content = Loc.T("DupFind");
                v.Progress.Visibility = Visibility.Collapsed;
                if (!failed) UpdateDupInfo();
                UpdateDupSelection();
            }
        }
    }

    private void RebuildDupRows()
    {
        var rows = new List<object>();
        if (_dupGroups != null)
            foreach (var g in _dupGroups)
            {
                rows.Add(g);
                if (g.IsExpanded) rows.AddRange(g.Files);
            }
        _dupRows.ReplaceAll(rows);
    }

    internal void OnDupGroupToggled(DupGroupVM g)
    {
        int i = _dupRows.IndexOf(g);
        if (i < 0) return;
        if (g.IsExpanded) _dupRows.InsertRange(i + 1, g.Files);
        else _dupRows.RemoveRange(i + 1, g.Files.Count);
    }

    // ================= Đánh dấu =================

    internal void OnDupCheckChanged(DupFileVM f, bool value)
    {
        _dupCheckedCount += value ? 1 : -1;
        _dupCheckedBytes += value ? f.Group.Size : -f.Group.Size;
        UpdateDupSelection();
    }

    internal void OnDupKeepOne()
    {
        DupView.SelInfo.Text = Loc.T("DupKeepOne");
        SetStatus(() => Loc.T("DupKeepOne"));
    }

    private void RecountDupChecks()
    {
        _dupCheckedCount = _dupCheckedBytes = 0;
        if (_dupGroups == null) return;
        foreach (var g in _dupGroups)
            foreach (var f in g.Files)
                if (f.IsChecked) { _dupCheckedCount++; _dupCheckedBytes += g.Size; }
    }

    /// <summary>Mỗi nhóm: đánh dấu mọi bản trừ bản sửa gần nhất. Bản có hard link không bao giờ được đánh dấu.</summary>
    private void DupSelectAllButNewest()
    {
        if (_dupGroups == null) return;
        foreach (var g in _dupGroups)
        {
            // Files đã xếp mới nhất trước; OrderBy giữ thứ tự khi trùng thời gian
            var keep = g.Files.OrderByDescending(f => f.File.LastWriteUtc).First();
            foreach (var f in g.Files) f.SetChecked(!ReferenceEquals(f, keep) && f.CanCheck);
            g.Refresh();
        }
        RecountDupChecks();
        UpdateDupSelection();
    }

    private void DupClearChecks()
    {
        if (_dupGroups == null) return;
        foreach (var g in _dupGroups)
        {
            foreach (var f in g.Files) f.SetChecked(false);
            g.Refresh();
        }
        RecountDupChecks();
        UpdateDupSelection();
    }

    private List<DupFileVM> DupSelectedFiles() =>
        DupView.List.SelectedItems.Cast<object>()
            .Select(o => o as DupFileVM ?? (o as DupGroupVM)?.Files.FirstOrDefault())
            .OfType<DupFileVM>().Distinct().ToList();

    private static bool IsInside<T>(object source, DependencyObject stop) where T : DependencyObject
    {
        for (var d = source as DependencyObject; d != null && d != stop; d = d is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d))
            if (d is T) return true;
        return false;
    }

    private void DupList_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        // Nhấp đúp vào ô đánh dấu hoặc mũi tên: đã xử lý bằng chính nút đó
        if (IsInside<ButtonBase>(e.OriginalSource, DupView.List)) return;
        if (e.OriginalSource is not DependencyObject d || ItemsControl.ContainerFromElement(DupView.List, d) is not ListViewItem item) return;
        if (item.Content is DupGroupVM g) g.IsExpanded = !g.IsExpanded;
        else if (item.Content is DupFileVM f) FileOps.SelectInExplorer(f.Path);
    }

    private void DupList_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        var sel = DupView.List.SelectedItem;
        switch (e.Key)
        {
            case Key.Delete:
                _ = DeleteDuplicatesAsync(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift));
                e.Handled = true;
                break;
            case Key.Space:
                foreach (var o in DupView.List.SelectedItems.Cast<object>().ToList())
                {
                    if (o is DupFileVM f) f.IsChecked = !f.IsChecked;
                    else if (o is DupGroupVM g && DupView.List.SelectedItems.Count == 1) g.IsExpanded = !g.IsExpanded;
                }
                e.Handled = true;
                break;
            case Key.Enter when sel is DupGroupVM g:
                g.IsExpanded = !g.IsExpanded;
                e.Handled = true;
                break;
            case Key.Enter when sel is DupFileVM f:
                FileOps.SelectInExplorer(f.Path);
                e.Handled = true;
                break;
            case Key.Left when sel is DupGroupVM { IsExpanded: true } g:
                g.IsExpanded = false;
                e.Handled = true;
                break;
            case Key.Right when sel is DupGroupVM { IsExpanded: false } g:
                g.IsExpanded = true;
                e.Handled = true;
                break;
        }
    }

    // ================= Xóa =================

    /// <summary>File vẫn đúng như lúc so sánh (cùng dung lượng và thời điểm sửa): nội dung coi như không đổi.</summary>
    private static bool DupUnchanged(DupFileVM f)
    {
        try
        {
            var fi = new FileInfo(f.Path);
            return fi.Exists && fi.Length == f.Group.Size && fi.LastWriteTimeUtc == f.File.LastWriteUtc;
        }
        catch { return false; }
    }

    private async Task DeleteDuplicatesAsync(bool permanent)
    {
        if (_dupGroups == null || _root == null || _dupCheckedCount == 0 || !CanStartDelete()) return;

        // Kiểm tra lại ngay trước khi xóa: nhóm phải còn ít nhất một bản không đánh dấu và chưa bị đổi,
        // bản sẽ xóa cũng phải còn nguyên như lúc so sánh. Không bao giờ xóa hết mọi bản của một nhóm.
        var files = new List<DupFileVM>();
        int skipped = 0;
        foreach (var g in _dupGroups)
        {
            var chosen = g.Files.Where(f => f.IsChecked).ToList();
            if (chosen.Count == 0) continue;
            bool keepOk = chosen.Count < g.Files.Count && g.Files.Any(f => !f.IsChecked && DupUnchanged(f));
            foreach (var f in chosen)
                if (keepOk && f.CanCheck && DupUnchanged(f)) files.Add(f);
                else skipped++;
        }
        if (files.Count == 0)
        {
            MessageBox.Show(this, Loc.F("DupChanged", FileOps.FormatCount(skipped)), "Diskat", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        foreach (var f in files)
        {
            if (FileOps.GetProtectionReason(f.Path) is { } reason)
            {
                MessageBox.Show(this, $"{reason}\n\n{f.Path}", Loc.T("MsgNotAllowed"), MessageBoxButton.OK, MessageBoxImage.Stop);
                return;
            }
        }

        long total = files.Sum(f => f.Group.Size);
        string label = files.Count == 1 ? files[0].Path : Loc.F("SelectedFiles", files.Count);
        string detail = Loc.T("DupConfirmDetail");
        string? warning = skipped > 0 ? Loc.F("DupChanged", FileOps.FormatCount(skipped)) : null;

        SetBusy(true);
        _dupBatch = true;
        _dupDirty = false;
        try
        {
            if (!ConfirmDelete(files.Count == 1 ? Loc.T("WhatFile") : Loc.F("WhatFiles", files.Count), label, total, detail, permanent, warning)) return;

            long freed = 0;
            foreach (var f in files)
            {
                // Bản giữ lại có thể đã bị xóa ở nơi khác trong lúc hộp thoại đang mở
                if (!f.Group.Files.Any(k => !k.IsChecked && File.Exists(k.Path))) continue;
                if (!await RunDeleteAsync(f.Path, false, permanent)) break;
                if (File.Exists(f.Path)) break; // người dùng hủy

                freed += f.Group.Size;
                var owner = FindNode(Path.GetDirectoryName(f.Path)!);
                if (owner != null) ApplyFileRemoved(owner, null, f.Group.Size);
                RemoveTopFilesUnder(f.Path); // cũng gỡ khỏi danh sách trùng lặp
            }

            AfterTreeChanged(Math.Max(0, Tree.SelectedIndex));
            if (freed > 0) { var fs = FileOps.FormatSize(freed); SetStatus(() => Loc.F("FreedShort", fs)); }
        }
        finally
        {
            _dupBatch = false;
            if (_dupDirty) AfterDupGroupsChanged();
            SetBusy(false);
        }
    }

    /// <summary>Gỡ các file nằm trong (hoặc chính là) path khỏi kết quả, khi chúng bị xóa ở bất kỳ đâu trong app.</summary>
    private void RemoveDuplicatesUnder(string path)
    {
        string prefix = path.TrimEnd('\\') + "\\";
        RemoveDuplicatesWhere(p => string.Equals(p, path, StringComparison.OrdinalIgnoreCase) || p.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Sau khi quét lại một thư mục: bỏ các file trong đó đã không còn tồn tại.</summary>
    private void PruneMissingDuplicatesUnder(string path)
    {
        string prefix = path.TrimEnd('\\') + "\\";
        RemoveDuplicatesWhere(p => p.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) && !File.Exists(p));
    }

    private void RemoveDuplicatesWhere(Func<string, bool> gone)
    {
        if (_dupGroups == null) return;
        bool changed = false;
        foreach (var g in _dupGroups)
            if (g.Files.RemoveAll(f => gone(f.Path)) > 0) changed = true;
        if (!changed) return;
        // Nhóm chỉ còn một bản, hoặc không còn bản nào xóa được, thì không còn là trùng lặp
        _dupGroups.RemoveAll(g => g.Files.Count < 2 || g.Files.All(f => !f.CanCheck));
        if (_dupBatch) _dupDirty = true;
        else AfterDupGroupsChanged();
    }

    private void AfterDupGroupsChanged()
    {
        if (_dupGroups == null) return;
        foreach (var g in _dupGroups)
        {
            // Bản giữ lại đã mất: bỏ đánh dấu cả nhóm để không bao giờ xóa hết
            if (g.Files.All(f => f.IsChecked))
                foreach (var f in g.Files) f.SetChecked(false);
            g.Refresh();
        }
        RecountDupChecks();
        RebuildDupRows();
        UpdateDupInfo();
        UpdateDupSelection();
    }
}
