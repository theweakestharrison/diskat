using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Diskat.Core;

namespace Diskat;

/// <summary>Một dòng trong tab Loại file / Tuổi file.</summary>
public sealed class StatRowVM
{
    public required string Label { get; init; }
    public string Extension { get; init; } = "";
    public int Index { get; init; }
    public long Size { get; init; }
    public long Count { get; init; }
    public double Percent { get; init; }
    public Brush Swatch { get; init; } = Brushes.Gray;
    public string SizeText => FileOps.FormatSize(Size);
    public string FilesText => FileOps.FormatCount(Count);
    public string PercentText => Percent.ToString("0.0", CultureInfo.InvariantCulture) + " %";
}

/// <summary>Tab Loại file, Tuổi file và thanh tìm file (theo tên, dung lượng, tuổi) ở tab File lớn nhất.</summary>
public partial class MainWindow
{
    // Danh sách "file lớn nhất" từ lần quét, và kết quả tìm kiếm (nếu đang hiển thị)
    private ObservableCollection<TopFileVM>? _topList;
    private ObservableCollection<TopFileVM>? _searchList;
    private bool _searchCapped;
    private CancellationTokenSource? _findCts;

    private const int MaxFindResults = 5000;
    private static readonly long[] FindSizes = [0, 1L << 20, 10L << 20, 100L << 20, 1L << 30];
    private static readonly string[] FindSizeLabels = ["", "1 MB", "10 MB", "100 MB", "1 GB"];
    private static readonly int[] FindAgeDays = [0, 30, 182, 365, 730, 1825];

    private static readonly Color[] TypeColors =
    [
        Color.FromRgb(0x4F, 0x8D, 0xF5), Color.FromRgb(0x2F, 0xB5, 0x9C), Color.FromRgb(0x6C, 0xB8, 0x4A),
        Color.FromRgb(0xF2, 0xB1, 0x2E), Color.FromRgb(0xF0, 0x7F, 0x3C), Color.FromRgb(0xE5, 0x56, 0x5B),
        Color.FromRgb(0xD9, 0x5C, 0xA8), Color.FromRgb(0x9B, 0x6C, 0xE0), Color.FromRgb(0x5C, 0x6B, 0xD8),
        Color.FromRgb(0x2E, 0xA8, 0xD6), Color.FromRgb(0xA3, 0xB8, 0x35), Color.FromRgb(0xB0, 0x7A, 0x52),
    ];
    // Mới (xanh) đến cũ (cam đất), giống báo cáo PDF
    private static readonly Color[] AgeColors =
    [
        Color.FromRgb(0x2F, 0x6F, 0xED), Color.FromRgb(0x2E, 0xA8, 0xD6), Color.FromRgb(0x2F, 0xB5, 0x9C),
        Color.FromRgb(0xA3, 0xB8, 0x35), Color.FromRgb(0xF2, 0xB1, 0x2E), Color.FromRgb(0xF0, 0x7F, 0x3C),
    ];
    private static readonly Brush OtherTypes = Frozen(new SolidColorBrush(Color.FromRgb(0x8E, 0x9A, 0xAF)));

    private static Brush Frozen(Brush b) { b.Freeze(); return b; }
    private static Brush BrushOf(Color c) => Frozen(new SolidColorBrush(c));

    // ================= Loại file / tuổi file =================

    private void ClearInsights()
    {
        TypesList.ItemsSource = null;
        AgesList.ItemsSource = null;
        AgesStrip.Children.Clear();
        AgesStrip.ColumnDefinitions.Clear();
        TypesNote.Text = AgesNote.Text = _root == null ? Loc.T("InsightsEmpty") : Loc.T("InsightsWait");
    }

    /// <summary>Gọi khi quét xong (thống kê được gộp từ các luồng quét) và khi đổi ngôn ngữ.</summary>
    private void LoadInsights()
    {
        if (_scanner == null || _root == null || IsScanning) { ClearInsights(); return; }

        var types = _scanner.GetFileTypes();
        long total = types.Sum(t => t.Size);
        TypesList.ItemsSource = types.Select((t, i) => new StatRowVM
        {
            Label = t.Extension.Length == 0 ? Loc.T("PdfNoExt") : t.Extension,
            Extension = t.Extension,
            Size = t.Size,
            Count = t.Count,
            Percent = total > 0 ? t.Size * 100.0 / total : 0,
            Swatch = i < TypeColors.Length ? BrushOf(TypeColors[i]) : OtherTypes,
        }).ToList();

        var ages = _scanner.GetAgeBuckets();
        long ageTotal = ages.Sum(a => a.Size);
        AgesList.ItemsSource = ages.Select((a, i) => new StatRowVM
        {
            Label = Loc.T("Age" + i),
            Index = i,
            Size = a.Size,
            Count = a.Count,
            Percent = ageTotal > 0 ? a.Size * 100.0 / ageTotal : 0,
            Swatch = BrushOf(AgeColors[i % AgeColors.Length]),
        }).ToList();

        AgesStrip.Children.Clear();
        AgesStrip.ColumnDefinitions.Clear();
        for (int i = 0; i < ages.Count; i++)
        {
            if (ages[i].Size <= 0) continue;
            AgesStrip.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(ages[i].Size, GridUnitType.Star) });
            var cell = new Border { Background = BrushOf(AgeColors[i % AgeColors.Length]), ToolTip = $"{Loc.T("Age" + i)}: {FileOps.FormatSize(ages[i].Size)}" };
            Grid.SetColumn(cell, AgesStrip.ColumnDefinitions.Count - 1);
            AgesStrip.Children.Add(cell);
        }
        UpdateInsightNotes();
    }

    private void UpdateInsightNotes()
    {
        if (_root == null || TypesList.ItemsSource is not ICollection<StatRowVM> types) return;
        string stale = _statsStale ? " " + Loc.T("InsightsStale") : "";
        TypesNote.Text = Loc.F("TypesNote", FileOps.FormatCount(types.Count), _root.FullPath) + stale;
        AgesNote.Text = Loc.T("AgesNote") + stale;
    }

    private void TypesList_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is DependencyObject d && ItemsControl.ContainerFromElement(TypesList, d) is ListViewItem) FindType_Click(sender, e);
    }

    /// <summary>Liệt kê toàn bộ file của loại đang chọn (không chỉ trong 500 file lớn nhất).</summary>
    private void FindType_Click(object sender, RoutedEventArgs e)
    {
        if (TypesList.SelectedItem is not StatRowVM { Extension.Length: > 0 } row) return;
        FindText.Text = "*" + row.Extension;
        FindSize.SelectedIndex = 0;
        FindAge.SelectedIndex = 0;
        RightTabs.SelectedItem = TopFilesTab;
        _ = RunFindAsync();
    }

    private void AgesList_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is DependencyObject d && ItemsControl.ContainerFromElement(AgesList, d) is ListViewItem) FindOlder_Click(sender, e);
    }

    /// <summary>Nhóm "1 đến 2 năm" → tìm file cũ hơn 1 năm (lớn nhất trước), để dọn file lâu không dùng.</summary>
    private void FindOlder_Click(object sender, RoutedEventArgs e)
    {
        if (AgesList.SelectedItem is not StatRowVM row) return;
        FindText.Text = "";
        FindSize.SelectedIndex = 0;
        FindAge.SelectedIndex = Math.Clamp(row.Index, 0, FindAgeDays.Length - 1);
        RightTabs.SelectedItem = TopFilesTab;
        _ = RunFindAsync();
    }

    // ================= Tìm file =================

    private void InitFindFilters()
    {
        int si = Math.Max(0, FindSize.SelectedIndex), ai = Math.Max(0, FindAge.SelectedIndex);
        FindSize.ItemsSource = FindSizeLabels.Select((l, i) => i == 0 ? Loc.T("FindSizeAny") : Loc.F("FindSizeMin", l)).ToList();
        FindAge.ItemsSource = FindAgeDays.Select((_, i) => Loc.T("FindAge" + i)).ToList();
        FindSize.SelectedIndex = si;
        FindAge.SelectedIndex = ai;
        // Rộng vừa lựa chọn dài nhất của ngôn ngữ hiện tại (vd. tiếng Bồ Đào Nha dài hơn tiếng Anh)
        FitComboWidth(FindSize, 110);
        FitComboWidth(FindAge, 130);
        if (_searchList == null) FindInfo.Text = Loc.T("FindTopHint");
        else UpdateFindInfo();
        FindBtn.Content = Loc.T(_findCts != null ? "FindStop" : "FindSearch");
    }

    private void FitComboWidth(ComboBox box, double min)
    {
        var face = new Typeface(box.FontFamily, box.FontStyle, box.FontWeight, box.FontStretch);
        double dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip, widest = 0;
        foreach (var item in box.Items)
        {
            var ft = new FormattedText(item?.ToString() ?? "", CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, face, box.FontSize, Brushes.Black, dpi);
            widest = Math.Max(widest, ft.WidthIncludingTrailingWhitespace);
        }
        box.Width = Math.Max(min, Math.Ceiling(widest) + 52); // lề trái 10, mũi tên 26, cộng chút dư cho font khác cỡ
    }

    private void FindText_TextChanged(object sender, TextChangedEventArgs e) =>
        FindTextHint.Visibility = FindText.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;

    private void FindText_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { _ = RunFindAsync(); e.Handled = true; }
    }

    private void FindSearch_Click(object sender, RoutedEventArgs e)
    {
        if (_findCts != null) { _findCts.Cancel(); return; }
        _ = RunFindAsync();
    }

    private void FindClear_Click(object sender, RoutedEventArgs e)
    {
        _findCts?.Cancel();
        ShowTopList();
    }

    /// <summary>Quay lại danh sách file lớn nhất của lần quét.</summary>
    private void ShowTopList()
    {
        _searchList = null;
        TopFiles.ItemsSource = _topList;
        FindClearBtn.Visibility = Visibility.Collapsed;
        FindInfo.Text = Loc.T("FindTopHint");
    }

    private void UpdateFindInfo()
    {
        if (_searchList == null) return;
        if (_searchList.Count == 0) { FindInfo.Text = Loc.T("FindNone"); return; }
        string text = Loc.F("FindResult", FileOps.FormatCount(_searchList.Count), FileOps.FormatSize(_searchList.Sum(f => f.Size)));
        if (_searchCapped) text += " " + Loc.F("FindCapped", FileOps.FormatCount(MaxFindResults));
        FindInfo.Text = text;
    }

    private async Task RunFindAsync()
    {
        if (_findCts != null) return;
        if (_root == null) return;
        if (IsScanning)
        {
            MessageBox.Show(this, Loc.T("MsgWaitScan"), "Diskat", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var patterns = FileFinder.ParsePatterns(FindText.Text);
        long minSize = FindSizes[Math.Max(0, FindSize.SelectedIndex)];
        int days = FindAgeDays[Math.Max(0, FindAge.SelectedIndex)];
        DateTime olderThan = days > 0 ? DateTime.UtcNow.AddDays(-days) : DateTime.MaxValue;
        string root = _root.FullPath;
        var scanRoot = _root;

        var cts = new CancellationTokenSource();
        _findCts = cts;
        FindBtn.Content = Loc.T("FindStop");
        var counter = new FileFinder.Counter();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        timer.Tick += (_, _) => FindInfo.Text = Loc.F("FindSearching", FileOps.FormatCount(Volatile.Read(ref counter.Found)), root);
        FindInfo.Text = Loc.F("FindSearching", "0", root);
        timer.Start();
        try
        {
            var result = await Task.Run(() => FileFinder.Find(root, patterns, minSize, olderThan, MaxFindResults, counter, cts.Token));
            if (!ReferenceEquals(scanRoot, _root)) return; // đã quét thư mục khác trong lúc tìm
            _searchList = new ObservableCollection<TopFileVM>(result.Files.Select(f =>
                new TopFileVM { Path = f.Path, Size = f.Size, LastWriteUtc = f.LastWriteUtc }));
            _searchCapped = result.Total > result.Files.Count;
            TopFiles.ItemsSource = _searchList;
            FindClearBtn.Visibility = Visibility.Visible;
            UpdateFindInfo();
        }
        catch (OperationCanceledException)
        {
            if (_searchList == null) FindInfo.Text = Loc.T("FindTopHint");
            else UpdateFindInfo();
        }
        catch (Exception ex)
        {
            FindInfo.Text = Loc.F("FindFailed", ex.Message);
        }
        finally
        {
            timer.Stop();
            if (ReferenceEquals(_findCts, cts)) _findCts = null;
            FindBtn.Content = Loc.T("FindSearch");
        }
    }

    /// <summary>Dừng tìm và bỏ kết quả cũ khi bắt đầu quét thư mục mới.</summary>
    private void ResetFind()
    {
        _findCts?.Cancel();
        _findCts = null;
        _topList = null;
        ShowTopList();
    }
}
