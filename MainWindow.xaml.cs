using System.Diagnostics;
using System.Security.Principal;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using Diskat.Core;
using Diskat.UI;

namespace Diskat;

public sealed class DriveVM
{
    public string Root { get; init; } = "";
    public string Title { get; init; } = "";
    public string UsedText { get; init; } = "";
    public string FreeText { get; init; } = "";
    public string Tip { get; init; } = "";
    public double UsedPercent { get; init; }
    public Brush BarBrush => UsedPercent >= 90 ? Palette.Danger : UsedPercent >= 75 ? Palette.Folder : (Brush)Application.Current.Resources["Accent"];
}

public partial class MainWindow : Window
{
    private Scanner? _scanner;
    private CancellationTokenSource? _cts;
    private Task? _scanTask;
    private DirNode? _root;
    private readonly Stopwatch _watch = new();
    private readonly DispatcherTimer _timer;
    private int _tick;
    private bool _isScanning;
    private bool IsScanning => _isScanning;

    private readonly CommandLine _cli = CommandLine.Parse(Environment.GetCommandLineArgs().Skip(1).ToArray());

    public MainWindow()
    {
        if (_cli.Lang != null) Loc.UseForSession(_cli.Lang);
        InitializeComponent();
        Tree.ItemsSource = _rows;
        InitDuplicates();

        _timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(200) };
        _timer.Tick += Timer_Tick;

        Map.ItemClicked += Map_ItemClicked;
        Map.ItemDoubleClicked += Map_ItemDoubleClicked;
        Map.HoverChanged += Map_HoverChanged;
        Map.ContextMenuOpening += Map_ContextMenuOpening;

        _isAdmin = IsAdministrator();
        if (_isAdmin) AdminBtn.Visibility = Visibility.Collapsed;

        Loc.LanguageChanged += ApplyLanguage;
        Theme.Changed += ApplyTheme;
        // Thanh tiêu đề tối phải đặt trước khi cửa sổ hiện lên, không thì Windows 10 vẽ thanh sáng trước
        SourceInitialized += (_, _) => Theme.SetTitleBar(this);

        Loaded += (_, _) =>
        {
            ApplyLanguage();
            UpdateActionButtons();
            if (_cli.ShellMenu is bool shellOn && !Updater.IsPackaged)
            {
                try { if (shellOn) ShellIntegration.Install(Loc.T("ShellVerb")); else ShellIntegration.Uninstall(); }
                catch { }
            }
            else if (!Updater.IsPackaged) ShellIntegration.RefreshIfInstalled(Loc.T("ShellVerb"));

            if (_cli.ScanPath != null) _ = RunCommandLineAsync(_cli);
            else if (_cli.Quit) { Application.Current.Shutdown(0); return; }
            if (!_cli.Quit) MaybeCheckForUpdatesOnStartup();
        };
        Closing += (_, _) => { _cts?.Cancel(); Loc.LanguageChanged -= ApplyLanguage; Theme.Changed -= ApplyTheme; };
    }

    // ================= Ngôn ngữ =================

    private bool _isAdmin;
    private Func<string> _status = () => Loc.T("Ready");

    /// <summary>Đặt dòng trạng thái dưới dạng hàm để có thể dịch lại khi đổi ngôn ngữ.</summary>
    private void SetStatus(Func<string> status)
    {
        _status = status;
        StatusText.Text = status();
    }

    /// <summary>Mở menu chọn ngôn ngữ ngay dưới nút.</summary>
    private void LangBtn_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = LangBtn, Placement = PlacementMode.Bottom };
        foreach (var lang in Loc.Languages)
        {
            var item = new MenuItem
            {
                Header = lang.Name,
                InputGestureText = lang.Code.ToUpperInvariant(),
                IsCheckable = true,
                IsChecked = lang.Code == Loc.Lang,
                Tag = lang.Code,
            };
            item.Click += (_, _) =>
            {
                Loc.SetLanguage(lang.Code);
                if (_root != null) FocusSelectedRow();
            };
            menu.Items.Add(item);
        }
        menu.IsOpen = true;
    }

    private void ApplyLanguage()
    {
        Title = Loc.T("WindowTitle") + (_isAdmin ? " (Administrator)" : "");
        LangLabel.Text = Loc.Lang.ToUpperInvariant();

        UpdateHeaderCaptions();
        InitFindFilters();
        InitDupFilters();
        LoadInsights();
        LoadDrives();
        foreach (var r in _rows) r.Refresh();
        TopFiles.Items.Refresh();
        Map.Redraw();
        Map_HoverChanged(null);
        UpdateStats();
        UpdateSelectionText();
        UpdateCompareBar();
        StatusText.Text = _status();
    }

    /// <summary>Sau khi đổi giao diện sáng / tối: XAML tự đổi màu, phần lấy màu từ mã (biểu tượng cây, thẻ ổ đĩa, bản đồ) vẽ lại.</summary>
    private void ApplyTheme()
    {
        foreach (var r in _rows) r.Refresh();
        LoadDrives();
        Map.Redraw();
    }

    // ================= Ổ đĩa =================

    private void LoadDrives()
    {
        var list = new List<DriveVM>();
        foreach (var d in DriveInfo.GetDrives())
        {
            try
            {
                if (!d.IsReady) continue;
                long total = d.TotalSize, free = d.TotalFreeSpace, used = total - free;
                string label = "";
                try { label = d.VolumeLabel; } catch { }
                if (string.IsNullOrWhiteSpace(label))
                    label = d.DriveType switch
                    {
                        DriveType.Removable => Loc.T("DriveUsb"),
                        DriveType.Network => Loc.T("DriveNetwork"),
                        DriveType.CDRom => Loc.T("DriveCd"),
                        _ => Loc.T("DriveLocal"),
                    };
                double pct = total > 0 ? used * 100.0 / total : 0;
                list.Add(new DriveVM
                {
                    Root = d.RootDirectory.FullName,
                    Title = $"{d.Name.TrimEnd('\\')}  {label}",
                    UsedText = $"{pct:0}%",
                    UsedPercent = pct,
                    FreeText = Loc.F("DriveFree", FileOps.FormatSize(free), FileOps.FormatSize(total)),
                    Tip = Loc.F("DriveTip", d.Name, d.DriveFormat, FileOps.FormatSize(used), FileOps.FormatSize(free)),
                });
            }
            catch { }
        }
        DrivesList.ItemsSource = list;
    }

    private void Drive_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string root })
        {
            PathBox.Text = root;
            _ = StartScanAsync(root);
        }
    }

    // ================= Quét =================

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFolderDialog { Title = Loc.T("BrowseTitle") };
        if (Directory.Exists(PathBox.Text)) dlg.InitialDirectory = PathBox.Text;
        if (dlg.ShowDialog(this) == true)
        {
            PathBox.Text = dlg.FolderName;
            _ = StartScanAsync(dlg.FolderName);
        }
    }

    private void Scan_Click(object sender, RoutedEventArgs e)
    {
        var p = PathBox.Text.Trim().Trim('"');
        if (p.Length == 0) { Browse_Click(sender, e); return; }
        _ = StartScanAsync(p);
    }

    private void PathBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) Scan_Click(sender, e);
    }

    private void Stop_Click(object sender, RoutedEventArgs e) => _cts?.Cancel();

    private async Task StartScanAsync(string path)
    {
        if (_busy)
        {
            MessageBox.Show(this, Loc.T("MsgBusy"), "Diskat", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (path.Length == 2 && path[1] == ':') path += "\\";
        if (!Directory.Exists(path))
        {
            MessageBox.Show(this, Loc.F("MsgNotFound", path), "Diskat", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (_scanTask is { IsCompleted: false })
        {
            _cts!.Cancel();
            try { await _scanTask!; } catch { }
        }

        _cts = new CancellationTokenSource();
        _statsStale = false;
        _scanner = new Scanner(path);
        _root = _scanner.Root;
        _root.IsExpanded = true;
        PathBox.Text = _root.FullPath;
        SuspendComparison(_root.FullPath);

        ResetTreeState();
        RebuildRows();
        Map.SetRoot(_root);
        UpdateMapHeader();
        ResetFind();
        EmptyState.Visibility = Visibility.Collapsed;

        SetScanningUi(true);
        ClearInsights();
        ResetDuplicates();
        _watch.Restart();
        _tick = 0;
        _timer.Start();

        _scanTask = _scanner.RunAsync(_cts.Token);
        await _scanTask;

        _timer.Stop();
        _watch.Stop();
        SetScanningUi(false);
        OnScanFinished(_cts.IsCancellationRequested);
    }

    private void SetScanningUi(bool scanning)
    {
        _isScanning = scanning;
        ScanBtn.Visibility = scanning ? Visibility.Collapsed : Visibility.Visible;
        StopBtn.Visibility = scanning ? Visibility.Visible : Visibility.Collapsed;
        ScanProgress.Visibility = scanning ? Visibility.Visible : Visibility.Collapsed;
        ScanProgress.IsIndeterminate = scanning;
        UpdateActionButtons();
    }

    private void Timer_Tick(object? sender, EventArgs e)
    {
        if (_scanner == null || _root == null) return;
        _tick++;
        UpdateStats();
        var sc = _scanner;
        SetStatus(() => Loc.F("Scanning", sc.CurrentPath ?? sc.Root.FullPath));

        // Sắp xếp lại mỗi giây để thư mục nặng nhất nổi lên đầu ngay trong lúc quét
        if (_tick % 5 == 0)
        {
            RebuildRows();
            Map.Redraw();
            UpdateMapHeader();
        }
        else
        {
            foreach (var r in _rows) r.Refresh();
        }
    }

    private void UpdateStats()
    {
        if (_root == null || _scanner == null) { StatsText.Text = ""; return; }
        var secs = _watch.Elapsed.TotalSeconds;
        string err = _scanner.Errors > 0 ? Loc.F("StatsBlocked", FileOps.FormatCount(_scanner.Errors)) : "";
        StatsText.Text = Loc.F("Stats",
            FileOps.FormatSize(Interlocked.Read(ref _root.Size)),
            FileOps.FormatCount(Interlocked.Read(ref _root.FileCount)),
            FileOps.FormatCount(Interlocked.Read(ref _root.DirCount)),
            secs) + err;
    }

    private void OnScanFinished(bool cancelled)
    {
        if (_root == null || _scanner == null) return;
        _scanStopped = cancelled;
        UpdateStats();
        RebuildRows();
        Map.SetRoot(Map.Root ?? _root);
        UpdateMapHeader();
        LoadTopFiles();
        LoadInsights();
        UpdateDupInfo();
        OnScanFinishedCompare(cancelled);

        double secs = _watch.Elapsed.TotalSeconds;
        long files = Interlocked.Read(ref _root.FileCount);
        string rate = FileOps.FormatCount((long)(files / Math.Max(secs, 0.001)));
        bool hintAdmin = _scanner.Errors > 0 && !_isAdmin;
        SetStatus(() => cancelled
            ? Loc.F("ScanStopped", secs)
            : Loc.F("ScanDone", secs, rate) + (hintAdmin ? Loc.T("ScanDoneBlocked") : ""));

        if (_rows.Count > 0 && Tree.SelectedItem == null)
            Tree.SelectedIndex = 0;
        FocusSelectedRow();
    }

    /// <summary>Đặt focus bàn phím vào dòng đang chọn để dùng phím mũi tên / Delete ngay.</summary>
    private void FocusSelectedRow()
    {
        Tree.UpdateLayout();
        if (Tree.SelectedIndex >= 0 &&
            Tree.ItemContainerGenerator.ContainerFromIndex(Tree.SelectedIndex) is System.Windows.Controls.ListViewItem item)
            item.Focus();
        else
            Tree.Focus();
    }

    // ================= Quyền Admin =================

    private static bool IsAdministrator()
    {
        try { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
        catch { return false; }
    }

    private const int ErrorCancelled = 1223; // người dùng bấm "No" ở hộp thoại UAC

    private void Admin_Click(object sender, RoutedEventArgs e)
    {
        // Đường dẫn kết thúc bằng '\' phải nhân đôi để không "nuốt" dấu ngoặc kép
        var p = _root?.FullPath;
        var arg = p != null ? "\"" + p + (p.EndsWith('\\') ? "\\" : "") + "\"" : "";

        // Bản cài từ Microsoft Store (MSIX): thử thêm alias "diskat.exe" khai báo trong manifest
        var targets = new List<string> { Environment.ProcessPath! };
        if (IsPackaged()) targets.Add("diskat.exe");

        foreach (var exe in targets)
        {
            try
            {
                Process.Start(new ProcessStartInfo(exe, arg) { UseShellExecute = true, Verb = "runas" });
                Close();
                return;
            }
            catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == ErrorCancelled)
            {
                return;
            }
            catch (System.ComponentModel.Win32Exception)
            {
                // thử cách tiếp theo
            }
        }
    }

    /// <summary>True nếu app đang chạy từ gói MSIX (cài qua Microsoft Store).</summary>
    private static bool IsPackaged()
    {
        try
        {
            int len = 0;
            return GetCurrentPackageFullName(ref len, null) != AppModelErrorNoPackage;
        }
        catch { return false; }
    }

    private const int AppModelErrorNoPackage = 15700;

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int GetCurrentPackageFullName(ref int packageFullNameLength, System.Text.StringBuilder? packageFullName);
}
