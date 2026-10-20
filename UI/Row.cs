using System.ComponentModel;
using System.Windows;
using System.Windows.Media;
using Diskat.Core;

namespace Diskat.UI;

public enum RowKind { Dir, File, Summary }

/// <summary>Một dòng trong cây đã được "làm phẳng" để ListView ảo hóa hiển thị nhanh.</summary>
public sealed class Row : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    public RowKind Kind { get; }
    public DirNode? Dir { get; }
    /// <summary>Thư mục chứa dòng này (với file/summary) hoặc thư mục cha (với thư mục).</summary>
    public DirNode? Owner { get; }
    public int Depth { get; }

    private readonly string _name;
    private long _fileSize;
    private readonly DateTime _fileTime;
    private readonly long _summaryCount;

    private Row(RowKind kind, DirNode? dir, DirNode? owner, int depth, string name, long size, DateTime time, long count = 0)
    {
        Kind = kind; Dir = dir; Owner = owner; Depth = depth;
        _name = name; _fileSize = size; _fileTime = time; _summaryCount = count;
    }

    public static Row ForDir(DirNode d, int depth) => new(RowKind.Dir, d, d.Parent, depth, d.Name, 0, default);
    public static Row ForFile(DirNode owner, FileItem f, int depth) => new(RowKind.File, null, owner, depth, f.Name, f.Size, f.LastWriteUtc);
    public static Row ForSummary(DirNode owner, long count, long size, int depth) =>
        new(RowKind.Summary, null, owner, depth, "", size, default, count);

    public string Name => Kind == RowKind.Summary ? Loc.F("MoreFiles", FileOps.FormatCount(_summaryCount)) : _name;
    public string FullPath => Kind switch
    {
        RowKind.Dir => Dir!.FullPath,
        RowKind.File => Path.Join(Owner!.FullPath, _name),
        _ => Owner!.FullPath,
    };

    public long SizeBytes => Kind == RowKind.Dir ? Interlocked.Read(ref Dir!.Size) : _fileSize;
    public string Size => FileOps.FormatSize(SizeBytes);

    public double Percent
    {
        get
        {
            long parent = Kind == RowKind.Dir
                ? (Dir!.Parent is { } p ? Interlocked.Read(ref p.Size) : SizeBytes)
                : Interlocked.Read(ref Owner!.Size);
            return parent <= 0 ? 0 : Math.Clamp(SizeBytes * 100.0 / parent, 0, 100);
        }
    }

    public string PercentText => Percent.ToString("0.0") + " %";

    public string Files => Kind switch
    {
        RowKind.Dir => FileOps.FormatCount(Interlocked.Read(ref Dir!.FileCount)),
        RowKind.Summary => FileOps.FormatCount(_summaryCount),
        _ => "",
    };

    public string Folders => Kind == RowKind.Dir ? FileOps.FormatCount(Interlocked.Read(ref Dir!.DirCount)) : "";

    // Giá trị thô dùng để sắp xếp
    public long FileCountValue => Kind == RowKind.Dir ? Interlocked.Read(ref Dir!.FileCount) : Kind == RowKind.Summary ? _summaryCount : 1;
    public long DirCountValue => Kind == RowKind.Dir ? Interlocked.Read(ref Dir!.DirCount) : -1;
    public long TimeValue => (Kind == RowKind.Dir ? Dir!.LastWriteUtc : _fileTime).Ticks;

    public string Modified
    {
        get
        {
            var t = Kind == RowKind.Dir ? Dir!.LastWriteUtc : _fileTime;
            return t == default || t.Year < 1980 ? "" : t.ToLocalTime().ToString(Loc.T("DateFormat"), System.Globalization.CultureInfo.InvariantCulture);
        }
    }

    // ---- So sánh với một lần quét đã lưu (cột "Thay đổi") ----

    /// <summary>Lần quét đang được so sánh, dùng chung cho mọi dòng của cây; null khi không so sánh.</summary>
    public static ScanComparison? Comparison { get; set; }

    private int BaselineIndex => Kind == RowKind.Dir && Comparison is { } c ? c.IndexOf(Dir!) : -2;

    /// <summary>Thư mục chưa có trong lần quét cũ.</summary>
    public bool IsNew => BaselineIndex == -1;
    public Visibility NewVisibility => IsNew ? Visibility.Visible : Visibility.Collapsed;
    public string NewLabel => Loc.T("CompareNew");

    /// <summary>Dung lượng tăng (+) / giảm (-) từ lần quét cũ. File không có số liệu cũ: luôn xếp cuối.</summary>
    public long ChangeValue => BaselineIndex switch
    {
        -2 => long.MinValue,
        -1 => SizeBytes,
        var i => SizeBytes - Comparison!.SizeAt(i),
    };

    public string ChangeText
    {
        get
        {
            long d = ChangeValue;
            if (d == long.MinValue || (d == 0 && !IsNew)) return "";
            return (d < 0 ? "-" : "+") + FileOps.FormatSize(Math.Abs(d));
        }
    }

    /// <summary>1: dùng thêm dung lượng, -1: đã giải phóng, 0: không đổi (XAML chọn màu GrowText / ShrinkText theo giao diện).</summary>
    public int ChangeSign => ChangeValue switch
    {
        long.MinValue => 0,
        > 0 => 1,
        < 0 => -1,
        _ => 0,
    };

    public string? ChangeTip
    {
        get
        {
            int i = BaselineIndex;
            if (i == -2) return null;
            string when = Comparison!.Info.ScannedUtc.ToLocalTime().ToString(Loc.T("DateFormat"), System.Globalization.CultureInfo.InvariantCulture);
            return i == -1 ? Loc.F("ChangeTipNew", when) : Loc.F("ChangeTip", FileOps.FormatSize(Comparison.SizeAt(i)), Size, when);
        }
    }

    public Thickness Indent => new(Depth * 18, 0, 0, 0);

    public bool HasChildren => Kind == RowKind.Dir && !Dir!.IsLink && (Dir.Children.Length > 0 || Dir.OwnFiles > 0 || !Dir.Scanned);

    private bool _isExpanded;
    public bool IsExpanded
    {
        get => _isExpanded;
        set { if (_isExpanded != value) { _isExpanded = value; if (Dir != null) Dir.IsExpanded = value; Raise(nameof(IsExpanded)); } }
    }

    public Geometry IconGeometry => Kind switch
    {
        RowKind.Dir => _isExpanded ? Icons.FolderOpen : Icons.Folder,
        RowKind.Summary => Icons.Dots,
        _ => Icons.File,
    };

    public Brush IconFill => Kind switch
    {
        RowKind.Dir when Dir!.AccessDenied => Palette.DangerSoft,
        RowKind.Dir when Dir!.IsLink => Palette.MutedSoft,
        RowKind.Dir => Palette.FolderFill,
        RowKind.Summary => Palette.Muted,
        _ => Palette.FileFill,
    };

    public Brush IconStroke => Kind switch
    {
        RowKind.Dir when Dir!.AccessDenied => Palette.Danger,
        RowKind.Dir when Dir!.IsLink => Palette.Muted,
        RowKind.Dir => Palette.Folder,
        RowKind.Summary => Palette.Muted,
        _ => Palette.FileIcon,
    };

    public string? Note => Kind == RowKind.Dir && Dir!.BadName ? Loc.T("NoteBadName")
                         : Kind == RowKind.Dir && Dir!.AccessDenied ? Loc.T("NoteDenied")
                         : Kind == RowKind.Dir && Dir!.IsLink ? Loc.T("NoteLink")
                         : null;

    public Brush BarBrush => Kind == RowKind.Dir && Dir!.Parent == null ? Palette.Accent : Palette.ForPercent(Percent);

    public FontWeight Weight => Kind == RowKind.Dir && Depth == 0 ? FontWeights.SemiBold : FontWeights.Normal;

    public void SetFileSize(long size) { _fileSize = size; Refresh(); }

    private static readonly PropertyChangedEventArgs AllChanged = new(string.Empty);
    public void Refresh() => PropertyChanged?.Invoke(this, AllChanged);
    private void Raise(string name)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        if (name == nameof(IsExpanded)) PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IconGeometry)));
    }
}

public static class Icons
{
    private static Geometry G(string s) { var g = Geometry.Parse(s); g.Freeze(); return g; }

    public static readonly Geometry Folder = G("M1.5,4 C1.5,3.2 2.1,2.5 3,2.5 L7.2,2.5 L9.2,4.5 L17,4.5 C17.9,4.5 18.5,5.1 18.5,6 L18.5,15.5 C18.5,16.4 17.9,17 17,17 L3,17 C2.1,17 1.5,16.4 1.5,15.5 Z");
    public static readonly Geometry FolderOpen = G("M1.5,4 C1.5,3.2 2.1,2.5 3,2.5 L7.2,2.5 L9.2,4.5 L16,4.5 C16.9,4.5 17.5,5.1 17.5,6 L17.5,8 L5.2,8 C4.5,8 4,8.4 3.8,9 L1.5,16 Z M4,9.5 L19.5,9.5 L17,17 L1.5,17 Z");
    public static readonly Geometry File = G("M4.5,1.5 L12,1.5 L16.5,6 L16.5,18.5 L4.5,18.5 Z M12,1.5 L12,6 L16.5,6");
    public static readonly Geometry Dots = G("M3,10 A1.6,1.6 0 1 1 6.2,10 A1.6,1.6 0 1 1 3,10 Z M8.4,10 A1.6,1.6 0 1 1 11.6,10 A1.6,1.6 0 1 1 8.4,10 Z M13.8,10 A1.6,1.6 0 1 1 17,10 A1.6,1.6 0 1 1 13.8,10 Z");
}

/// <summary>Màu biểu tượng / thanh trong cây, lấy từ giao diện hiện tại (Themes/Light.xaml, Dark.xaml).</summary>
public static class Palette
{
    private static SolidColorBrush B(byte r, byte g, byte b) { var x = new SolidColorBrush(Color.FromRgb(r, g, b)); x.Freeze(); return x; }

    // Giá trị ban đầu là màu sáng, dùng khi chưa có Application (ví dụ chỉ xuất báo cáo)
    public static Brush Folder { get; private set; } = B(0xD9, 0x96, 0x1A);
    public static Brush FolderFill { get; private set; } = B(0xF6, 0xC3, 0x4F);
    public static Brush FileIcon { get; private set; } = B(0x5B, 0x8D, 0xEF);
    public static Brush FileFill { get; private set; } = B(0xEA, 0xF1, 0xFD);
    public static Brush Muted { get; private set; } = B(0x9A, 0xA0, 0xAB);
    public static Brush MutedSoft { get; private set; } = B(0xE4, 0xE7, 0xEC);
    public static Brush Danger { get; private set; } = B(0xD9, 0x3B, 0x3B);
    public static Brush DangerSoft { get; private set; } = B(0xF9, 0xD7, 0xD7);
    public static Brush Accent { get; private set; } = B(0x2F, 0x6F, 0xED);

    /// <summary>Đọc lại màu sau khi đổi giao diện (UI/Theme.cs gọi).</summary>
    public static void Load()
    {
        static Brush R(string key) => (Brush)Application.Current.Resources[key];
        Folder = R("FolderStroke");
        FolderFill = R("FolderFill");
        FileIcon = R("FileStroke");
        FileFill = R("FileFill");
        Muted = R("IconMuted");
        MutedSoft = R("IconMutedSoft");
        Danger = R("Danger");
        DangerSoft = R("IconDangerSoft");
        Accent = R("Accent");
    }

    private static readonly Brush[] Bars =
    [
        B(0x4C, 0xAF, 0x7D), // < 10%
        B(0x7C, 0xB3, 0x42), // < 25%
        B(0xE8, 0xA3, 0x17), // < 50%
        B(0xEF, 0x7B, 0x2D), // < 75%
        B(0xE0, 0x4A, 0x3F), // >= 75%
    ];

    public static Brush ForPercent(double p) =>
        p < 10 ? Bars[0] : p < 25 ? Bars[1] : p < 50 ? Bars[2] : p < 75 ? Bars[3] : Bars[4];
}
