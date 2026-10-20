using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using Diskat.Core;
using Diskat.UI;

namespace Diskat;

public sealed class TopFileVM
{
    public required string Path { get; init; }
    public required long Size { get; init; }
    public DateTime LastWriteUtc { get; init; }
    public string Name => System.IO.Path.GetFileName(Path);
    public string Folder => System.IO.Path.GetDirectoryName(Path) ?? "";
    public string SizeText => FileOps.FormatSize(Size);
    public string Modified => LastWriteUtc.Year < 1980 ? "" : LastWriteUtc.ToLocalTime().ToString(Loc.T("DateFormat"), System.Globalization.CultureInfo.InvariantCulture);
}

public partial class MainWindow
{
    private Row? SelectedRow => Tree.SelectedItem is Row { Kind: not RowKind.Summary } r ? r : null;

    // ================= Menu cây =================

    private void MenuExplorer_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedRow is { } r)
        {
            if (r.Kind == RowKind.Dir) FileOps.ShowInExplorer(r.FullPath);
            else FileOps.SelectInExplorer(r.FullPath);
        }
    }

    private void MenuOpen_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedRow is { } r) FileOps.OpenWithShell(r.FullPath);
    }

    private void MenuCopy_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedRow is { } r) TrySetClipboard(r.FullPath);
    }

    private void MenuMap_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedRow is not { } r) return;
        var target = r.Kind == RowKind.Dir ? r.Dir : r.Owner;
        if (target == null || target.IsLink) return;
        Map.SetRoot(target);
        UpdateMapHeader();
        RightTabs.SelectedIndex = 0;
    }

    private void MenuRescan_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedRow is { } r)
        {
            var target = r.Kind == RowKind.Dir ? r.Dir! : r.Owner!;
            _ = RescanNodeAsync(target);
        }
    }

    private void MenuRecycle_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedRow is { } r) _ = DeleteRowAsync(r, permanent: false);
    }

    private void MenuDelete_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedRow is { } r) _ = DeleteRowAsync(r, permanent: true);
    }

    private static void TrySetClipboard(string text)
    {
        for (int i = 0; i < 5; i++)
        {
            try { Clipboard.SetText(text); return; }
            catch { Thread.Sleep(30); }
        }
    }

    // ================= Xóa =================

    // Một thao tác xóa / quét lại tại một thời điểm (chặn cả phím Del, F5 khi lớp phủ đang hiện)
    private bool _busy;
    private bool IsBusy => _isScanning || _busy;

    private void SetBusy(bool busy)
    {
        _busy = busy;
        UpdateActionButtons();
    }

    /// <summary>Trả về true nếu được phép bắt đầu xóa; nếu không thì báo cho người dùng.</summary>
    private bool CanStartDelete()
    {
        if (_busy) return false;
        if (!IsScanning) return true;
        MessageBox.Show(this, Loc.T("MsgWaitScan"), "Diskat", MessageBoxButton.OK, MessageBoxImage.Information);
        return false;
    }

    private bool ConfirmDelete(string what, string path, long size, string detail, bool permanent, string? warning = null) =>
        ConfirmDialog.Ask(this, permanent, what, path, FileOps.FormatSize(size), detail, warning);

    private async Task<bool> RunDeleteAsync(string path, bool isDir, bool permanent)
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        while (true)
        {
            Exception error;
            BusyText.Text = Loc.T(permanent ? "DeletingPerm" : "Recycling");
            BusyOverlay.Visibility = Visibility.Visible;
            try
            {
                await Task.Run(() =>
                {
                    if (permanent) FileOps.DeletePermanently(path, isDir);
                    else FileOps.SendToRecycleBin(path, hwnd);
                });
                return true;
            }
            catch (Exception ex) { error = ex; }
            finally { BusyOverlay.Visibility = Visibility.Collapsed; }

            // Có chương trình đang giữ file? Tìm ra chúng thay vì chỉ báo "đang được sử dụng"
            LockReport? report = null;
            if (Path.Exists(path))
            {
                BusyText.Text = Loc.T("LockSearching");
                BusyOverlay.Visibility = Visibility.Visible;
                try { report = await Task.Run(() => LockFinder.Inspect(path, isDir)); }
                catch { }
                finally { BusyOverlay.Visibility = Visibility.Collapsed; }
            }

            bool inUse = report != null && (LockFinder.IsInUseError(error) || report.LockedFiles.Count > 0 || report.Processes.Count > 0);
            if (!inUse)
            {
                MessageBox.Show(this, Loc.F("MsgDeleteFailed", path, error.Message), Loc.T("MsgDeleteErrorTitle"), MessageBoxButton.OK, MessageBoxImage.Error);
                return false;
            }

            switch (LockedDialog.Ask(this, path, report!))
            {
                case LockAction.Retry:
                    continue;
                case LockAction.DeleteOnReboot:
                    ScheduleDeleteOnReboot(path, isDir, permanent);
                    return false;
                default:
                    return false;
            }
        }
    }

    /// <summary>Hẹn xóa khi Windows khởi động lại. Windows chỉ cho phép việc này khi chạy bằng quyền Admin.</summary>
    private void ScheduleDeleteOnReboot(string path, bool isDir, bool permanent)
    {
        if (!_isAdmin)
        {
            MessageBox.Show(this, Loc.T("LockRebootAdmin"), Loc.T("LockTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        // Xóa lúc khởi động không đi qua Thùng rác: hỏi lại nếu người dùng đã chọn "Thùng rác"
        if (!permanent && MessageBox.Show(this, Loc.T("LockRebootPermanent"), Loc.T("LockTitle"),
                MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
            return;

        bool ok;
        try { ok = LockFinder.ScheduleDeleteOnReboot(path, isDir); }
        catch { ok = false; }
        if (ok)
        {
            SetStatus(() => Loc.F("LockRebootStatus", path));
            MessageBox.Show(this, Loc.F("LockRebootDone", path), Loc.T("LockTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
        }
        else
            MessageBox.Show(this, Loc.F("LockRebootFailed", path), Loc.T("LockTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
    }

    private async Task DeleteRowAsync(Row row, bool permanent)
    {
        if (row.Kind == RowKind.Summary || !CanStartDelete()) return;
        if (row.Kind == RowKind.Dir && ReferenceEquals(row.Dir, _root))
        {
            MessageBox.Show(this, Loc.T("MsgRootDelete"), "Diskat",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        string path = row.FullPath;
        if (FileOps.GetProtectionReason(path) is { } reason)
        {
            MessageBox.Show(this, $"{reason}\n\n{path}", Loc.T("MsgNotAllowed"), MessageBoxButton.OK, MessageBoxImage.Stop);
            return;
        }

        bool isDir = row.Kind == RowKind.Dir;
        long size = row.SizeBytes;
        string detail = isDir ? Loc.F("DetailDir", row.Files, row.Folders) : "";
        // Thư mục chưa quét xong (đã bấm Dừng / bị chặn quyền): số liệu trong hộp thoại có thể thiếu
        string? warning = isDir && !row.Dir!.IsFullyScanned() ? Loc.T("ConfirmIncomplete") : null;

        SetBusy(true);
        try
        {
            if (!ConfirmDelete(Loc.T(isDir ? "WhatFolder" : "WhatFile"), path, size, detail, permanent, warning)) return;

            int index = _rows.IndexOf(row);
            await RunDeleteAsync(path, isDir, permanent);

            if (isDir)
            {
                var node = row.Dir!;
                if (!Directory.Exists(path))
                {
                    node.Detach();
                    _dirRows.Remove(node);
                    RemoveTopFilesUnder(path);
                    AfterTreeChanged(index);
                    SetStatus(() => Loc.F("Freed", FileOps.FormatSize(size), path));
                }
                else
                {
                    // Xóa không trọn vẹn (bị hủy hoặc lỗi): quét lại để số liệu chính xác
                    await RescanCoreAsync(node);
                }
            }
            else if (!File.Exists(path))
            {
                ApplyFileRemoved(row.Owner!, row, size);
                RemoveTopFilesUnder(path);
                AfterTreeChanged(index);
                SetStatus(() => Loc.F("Freed", FileOps.FormatSize(size), path));
            }
        }
        finally { SetBusy(false); }
    }

    private void ApplyFileRemoved(DirNode owner, Row? fileRow, long size)
    {
        owner.RemoveFile(size);
        if (fileRow != null && _fileRows.TryGetValue(owner, out var list)) list.Remove(fileRow);
        else _fileRows.Remove(owner);
    }

    /// <summary>Cập nhật lại cây/bản đồ sau khi xóa và chọn dòng kế bên.</summary>
    private void AfterTreeChanged(int oldIndex)
    {
        _statsStale = true;
        UpdateInsightNotes();
        // Thư mục đang xem trên bản đồ (hoặc một thư mục cha của nó) đã bị xóa
        if (Map.Root != null && _root != null && !Map.Root.IsAttachedTo(_root))
            Map.SetRoot(_root);

        _suppressSelection = true;
        try { RebuildRows(); }
        finally { _suppressSelection = false; }

        if (_rows.Count > 0)
        {
            var next = _rows[Math.Clamp(oldIndex, 0, _rows.Count - 1)];
            SelectRow(next);
            FocusSelectedRow();
        }
        Map.SetRoot(Map.Root ?? _root);
        UpdateMapHeader();
        UpdateStats();
    }

    // ================= Quét lại một thư mục =================

    private async Task RescanNodeAsync(DirNode node)
    {
        if (IsBusy || _root == null || node.IsLink) return;
        if (ReferenceEquals(node, _root)) { await StartScanAsync(_root.FullPath); return; }

        SetBusy(true);
        try { await RescanCoreAsync(node); }
        finally { SetBusy(false); }
    }

    private async Task RescanCoreAsync(DirNode node)
    {
        if (_root == null || !node.IsAttachedTo(_root)) return;
        var path = node.FullPath;
        if (!Directory.Exists(path))
        {
            node.Detach();
            _dirRows.Remove(node);
            AfterTreeChanged(_rows.Count);
            return;
        }

        SetStatus(() => Loc.F("Rescanning", path));
        ScanProgress.Visibility = Visibility.Visible;
        ScanProgress.IsIndeterminate = true;
        var sc = new Scanner(path);
        await sc.RunAsync(CancellationToken.None);
        ScanProgress.IsIndeterminate = false;
        ScanProgress.Visibility = Visibility.Collapsed;

        var fresh = sc.Root;
        long dSize = fresh.Size - node.Size, dFiles = fresh.FileCount - node.FileCount, dDirs = fresh.DirCount - node.DirCount;
        node.Size = fresh.Size;
        node.FileCount = fresh.FileCount;
        node.DirCount = fresh.DirCount;
        node.OwnSize = fresh.OwnSize;
        node.OwnFiles = fresh.OwnFiles;
        node.AccessDenied = fresh.AccessDenied;
        foreach (var c in fresh.Children) c.Parent = node;
        node.Children = fresh.Children;
        for (var p = node.Parent; p != null; p = p.Parent)
        {
            p.Size += dSize;
            p.FileCount += dFiles;
            p.DirCount += dDirs;
        }

        _fileRows.Clear();
        PruneMissingTopFilesUnder(path);
        AfterTreeChanged(Math.Max(0, Tree.SelectedIndex));
        var newSize = FileOps.FormatSize(node.Size);
        SetStatus(() => Loc.F("Rescanned", path, newSize));
    }

    // ================= File lớn nhất =================

    private void LoadTopFiles()
    {
        if (_scanner == null) return;
        _topList = new System.Collections.ObjectModel.ObservableCollection<TopFileVM>(
            _scanner.GetTopFiles().Select(f => new TopFileVM { Path = f.Path, Size = f.Size, LastWriteUtc = f.LastWriteUtc }));
        if (_searchList == null) TopFiles.ItemsSource = _topList;
    }

    /// <summary>Danh sách file lớn nhất và kết quả tìm kiếm (cả hai cần cập nhật khi xóa).</summary>
    private IEnumerable<System.Collections.ObjectModel.ObservableCollection<TopFileVM>> FileLists()
    {
        if (_topList != null) yield return _topList;
        if (_searchList != null) yield return _searchList;
    }

    private void RemoveTopFilesUnder(string path)
    {
        string prefix = path.TrimEnd('\\') + "\\";
        foreach (var list in FileLists())
        {
            for (int i = list.Count - 1; i >= 0; i--)
            {
                var p = list[i].Path;
                if (string.Equals(p, path, StringComparison.OrdinalIgnoreCase) || p.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    list.RemoveAt(i);
            }
        }
        UpdateFindInfo();
        RemoveDuplicatesUnder(path);
    }

    /// <summary>Sau khi quét lại một thư mục: bỏ các file trong đó đã không còn tồn tại.</summary>
    private void PruneMissingTopFilesUnder(string path)
    {
        string prefix = path.TrimEnd('\\') + "\\";
        foreach (var list in FileLists())
            for (int i = list.Count - 1; i >= 0; i--)
                if (list[i].Path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) && !File.Exists(list[i].Path))
                    list.RemoveAt(i);
        UpdateFindInfo();
        PruneMissingDuplicatesUnder(path);
    }

    private List<TopFileVM> SelectedTopFiles => TopFiles.SelectedItems.Cast<TopFileVM>().ToList();

    private void TopExplorer_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedTopFiles.FirstOrDefault() is { } f) FileOps.SelectInExplorer(f.Path);
    }

    private void TopOpen_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedTopFiles.FirstOrDefault() is { } f) FileOps.OpenWithShell(f.Path);
    }

    private void TopCopy_Click(object sender, RoutedEventArgs e)
    {
        var files = SelectedTopFiles;
        if (files.Count > 0) TrySetClipboard(string.Join(Environment.NewLine, files.Select(f => f.Path)));
    }

    private void TopRecycle_Click(object sender, RoutedEventArgs e) => _ = DeleteTopFilesAsync(false);
    private void TopDelete_Click(object sender, RoutedEventArgs e) => _ = DeleteTopFilesAsync(true);

    private void TopFiles_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (TopFiles.SelectedItem is TopFileVM f) FileOps.SelectInExplorer(f.Path);
    }

    private void TopFiles_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Delete)
        {
            _ = DeleteTopFilesAsync(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift));
            e.Handled = true;
        }
    }

    private async Task DeleteTopFilesAsync(bool permanent)
    {
        var files = SelectedTopFiles;
        if (files.Count == 0 || _root == null || !CanStartDelete()) return;

        // File đã bị xóa ở nơi khác: chỉ gỡ khỏi danh sách, không trừ dung lượng lần nữa
        foreach (var gone in files.Where(f => !File.Exists(f.Path)).ToList())
        {
            RemoveTopFilesUnder(gone.Path);
            files.Remove(gone);
        }
        if (files.Count == 0) return;

        foreach (var f in files)
        {
            if (FileOps.GetProtectionReason(f.Path) is { } reason)
            {
                MessageBox.Show(this, $"{reason}\n\n{f.Path}", Loc.T("MsgNotAllowed"), MessageBoxButton.OK, MessageBoxImage.Stop);
                return;
            }
        }

        long total = files.Sum(f => f.Size);
        string label = files.Count == 1 ? files[0].Path : Loc.F("SelectedFiles", files.Count);

        SetBusy(true);
        try
        {
            if (!ConfirmDelete(files.Count == 1 ? Loc.T("WhatFile") : Loc.F("WhatFiles", files.Count), label, total, "", permanent)) return;

            long freed = 0;
            foreach (var f in files)
            {
                if (!await RunDeleteAsync(f.Path, false, permanent)) break;
                if (File.Exists(f.Path)) break; // người dùng hủy

                freed += f.Size;
                var owner = FindNode(Path.GetDirectoryName(f.Path)!);
                if (owner != null) ApplyFileRemoved(owner, null, f.Size);
                RemoveTopFilesUnder(f.Path);
            }

            AfterTreeChanged(Math.Max(0, Tree.SelectedIndex));
            if (freed > 0) { var fs = FileOps.FormatSize(freed); SetStatus(() => Loc.F("FreedShort", fs)); }
        }
        finally { SetBusy(false); }
    }

    private DirNode? FindNode(string dirPath)
    {
        if (_root == null) return null;
        string rel;
        try { rel = Path.GetRelativePath(_root.FullPath, dirPath); } catch { return null; }
        if (rel == ".") return _root;
        if (rel.StartsWith("..") || Path.IsPathRooted(rel)) return null;

        var cur = _root;
        foreach (var part in rel.Split('\\', StringSplitOptions.RemoveEmptyEntries))
        {
            var next = cur.Children.FirstOrDefault(c => string.Equals(c.Name, part, StringComparison.OrdinalIgnoreCase));
            if (next == null) return null;
            cur = next;
        }
        return cur;
    }
}
