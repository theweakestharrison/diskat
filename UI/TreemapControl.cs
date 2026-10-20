using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Diskat.Core;

namespace Diskat.UI;

public sealed class TreemapItem
{
    public DirNode? Node;          // thư mục (null nếu là file / nhóm file)
    public DirNode Owner = null!;  // thư mục chứa
    public string? FilePath;       // file đơn lẻ
    public string Label = "";
    public long Size;
    public Rect Rect;
    public int Depth;
    public int Color;
    public bool IsFileGroup;
}

/// <summary>Bản đồ dung lượng dạng "squarified treemap", 2 cấp, vẽ trực tiếp bằng DrawingVisual.</summary>
public sealed class TreemapControl : FrameworkElement
{
    private readonly DrawingVisual _content = new();
    private readonly DrawingVisual _overlay = new();
    private readonly VisualCollection _visuals;
    private readonly List<TreemapItem> _items = new();
    // File nằm trực tiếp trong Root: tải ở luồng nền, giữ tối đa MaxRootFiles file lớn nhất
    private const int MaxRootFiles = 1000;
    private List<FileItem> _rootFiles = new();
    private int _restFilesCount;
    private long _restFilesSize;
    private DirNode? _filesFor;
    private int _loadVersion;
    private TreemapItem? _hover;

    public DirNode? Root { get; private set; }

    public event Action<TreemapItem>? ItemClicked;
    public event Action<TreemapItem>? ItemDoubleClicked;
    public event Action<TreemapItem?>? HoverChanged;

    public TreemapControl()
    {
        _visuals = new VisualCollection(this) { _content, _overlay };
        ClipToBounds = true;
        Focusable = false;
    }

    protected override int VisualChildrenCount => _visuals.Count;
    protected override Visual GetVisualChild(int index) => _visuals[index];

    public void SetRoot(DirNode? root)
    {
        Root = root;
        _rootFiles = new List<FileItem>();
        _restFilesCount = 0;
        _restFilesSize = 0;
        _filesFor = null;
        int version = ++_loadVersion;

        if (root != null && root.OwnFiles > 0)
        {
            // Liệt kê file ở luồng nền: thư mục có hàng trăm nghìn file hoặc ổ mạng không làm đứng giao diện
            string path = root.FullPath;
            Task.Run(() => LoadFiles(path)).ContinueWith(t =>
            {
                if (t.IsFaulted || version != _loadVersion || !ReferenceEquals(Root, root)) return;
                (_rootFiles, _restFilesCount, _restFilesSize) = t.Result;
                _filesFor = root;
                Redraw();
            }, TaskScheduler.FromCurrentSynchronizationContext());
        }
        Redraw();
    }

    private static (List<FileItem> files, int restCount, long restSize) LoadFiles(string path)
    {
        var all = FileOps.ListFiles(path);
        all.Sort((a, b) => b.Size.CompareTo(a.Size));
        if (all.Count <= MaxRootFiles) return (all, 0, 0);

        long rest = 0;
        for (int i = MaxRootFiles; i < all.Count; i++) rest += all[i].Size;
        int restCount = all.Count - MaxRootFiles;
        all.RemoveRange(MaxRootFiles, restCount);
        return (all, restCount, rest);
    }

    public void Redraw()
    {
        _hover = null;
        BuildAndRender();
        RenderOverlay();
    }

    protected override void OnRenderSizeChanged(SizeChangedInfo sizeInfo)
    {
        base.OnRenderSizeChanged(sizeInfo);
        Redraw();
    }

    // ---------------- Bảng màu ----------------

    private static readonly Color[] BaseColors =
    [
        Color.FromRgb(0x4F, 0x8D, 0xF5), Color.FromRgb(0x2F, 0xB5, 0x9C), Color.FromRgb(0x6C, 0xB8, 0x4A),
        Color.FromRgb(0xF2, 0xB1, 0x2E), Color.FromRgb(0xF0, 0x7F, 0x3C), Color.FromRgb(0xE5, 0x56, 0x5B),
        Color.FromRgb(0xD9, 0x5C, 0xA8), Color.FromRgb(0x9B, 0x6C, 0xE0), Color.FromRgb(0x5C, 0x6B, 0xD8),
        Color.FromRgb(0x2E, 0xA8, 0xD6), Color.FromRgb(0xA3, 0xB8, 0x35), Color.FromRgb(0xB0, 0x7A, 0x52),
    ];
    private static readonly Color FileColor = Color.FromRgb(0x8E, 0x9A, 0xAF);

    private static readonly Dictionary<(int, int), Brush> BrushCache = new();
    private static Brush GetBrush(int color, int depth)
    {
        if (BrushCache.TryGetValue((color, depth), out var b)) return b;
        var c = color < 0 ? FileColor : BaseColors[color % BaseColors.Length];
        if (depth > 0) c = Mix(c, Colors.White, 0.25);
        var g = new LinearGradientBrush(Mix(c, Colors.White, 0.22), Mix(c, Colors.Black, 0.12), new Point(0, 0), new Point(1, 1));
        g.Freeze();
        BrushCache[(color, depth)] = g;
        return g;
    }

    private static readonly Brush HeaderBrush = Frozen(new SolidColorBrush(Color.FromArgb(0x40, 0, 0, 0)));
    private static readonly Pen BorderPen = Frozen(new Pen(new SolidColorBrush(Color.FromArgb(0xC0, 0xFF, 0xFF, 0xFF)), 1));
    private static readonly Pen HoverPen = Frozen(new Pen(Brushes.White, 2.5));
    private static readonly Pen HoverPenOuter = Frozen(new Pen(new SolidColorBrush(Color.FromArgb(0xA0, 0, 0, 0)), 4.5));
    private static readonly Brush HoverFill = Frozen(new SolidColorBrush(Color.FromArgb(0x30, 0xFF, 0xFF, 0xFF)));
    private static readonly Typeface Face = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
    private static readonly Typeface FaceLight = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);

    private static T Frozen<T>(T f) where T : Freezable { f.Freeze(); return f; }

    private static Color Mix(Color a, Color b, double t) => Color.FromRgb(
        (byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));

    // ---------------- Bố cục ----------------

    private struct Entry
    {
        public long Size;
        public DirNode? Node;
        public string? FilePath;
        public string Label;
        public bool IsGroup;
    }

    private const int MaxItemsPerLevel = 1500;

    private List<Entry> CollectEntries(DirNode dir, bool individualFiles)
    {
        var list = new List<Entry>(dir.Children.Length + 8);
        foreach (var c in dir.Children)
        {
            long s = Interlocked.Read(ref c.Size);
            if (s > 0) list.Add(new Entry { Size = s, Node = c, Label = c.Name });
        }
        if (individualFiles && ReferenceEquals(dir, Root) && ReferenceEquals(_filesFor, Root) && _rootFiles.Count > 0)
        {
            string basePath = dir.FullPath;
            foreach (var f in _rootFiles)
                if (f.Size > 0) list.Add(new Entry { Size = f.Size, FilePath = Path.Join(basePath, f.Name), Label = f.Name });
            if (_restFilesSize > 0)
                list.Add(new Entry { Size = _restFilesSize, IsGroup = true, Label = Loc.F("MapFiles", FileOps.FormatCount(_restFilesCount)) });
        }
        else if (dir.OwnSize > 0)
        {
            list.Add(new Entry { Size = dir.OwnSize, IsGroup = true, Label = Loc.F("MapFiles", FileOps.FormatCount(dir.OwnFiles)) });
        }

        list.Sort((a, b) => b.Size.CompareTo(a.Size));
        if (list.Count > MaxItemsPerLevel)
        {
            long rest = 0;
            for (int i = MaxItemsPerLevel - 1; i < list.Count; i++) rest += list[i].Size;
            int restCount = list.Count - (MaxItemsPerLevel - 1);
            list.RemoveRange(MaxItemsPerLevel - 1, restCount);
            list.Add(new Entry { Size = rest, IsGroup = true, Label = Loc.F("MapOthers", FileOps.FormatCount(restCount)) });
        }
        return list;
    }

    private static void Squarify(List<Entry> items, Rect rect, Action<int, Rect> place)
    {
        double total = 0;
        foreach (var e in items) total += e.Size;
        if (total <= 0 || rect.Width < 1 || rect.Height < 1) return;

        double scale = rect.Width * rect.Height / total;
        int n = items.Count, i = 0;
        double rx = rect.X, ry = rect.Y, rw = rect.Width, rh = rect.Height;

        while (i < n)
        {
            double side = Math.Min(rw, rh);
            if (side <= 0.5) break;

            int j = i;
            double rowSum = 0, best = double.MaxValue;
            double amax = items[i].Size * scale;
            while (j < n)
            {
                double a = items[j].Size * scale;
                if (a <= 0) { j++; continue; }
                double s = rowSum + a;
                double w2 = side * side, s2 = s * s;
                double worst = Math.Max(w2 * amax / s2, s2 / (w2 * a));
                if (worst > best) break;
                best = worst; rowSum = s; j++;
            }
            if (rowSum <= 0) break;

            double thick = rowSum / side;
            if (rw >= rh)
            {
                double y = ry;
                for (int k = i; k < j; k++)
                {
                    double h = items[k].Size * scale / thick;
                    place(k, new Rect(rx, y, thick, h));
                    y += h;
                }
                rx += thick; rw = Math.Max(0, rw - thick);
            }
            else
            {
                double x = rx;
                for (int k = i; k < j; k++)
                {
                    double w = items[k].Size * scale / thick;
                    place(k, new Rect(x, ry, w, thick));
                    x += w;
                }
                ry += thick; rh = Math.Max(0, rh - thick);
            }
            i = j;
        }
    }

    private void BuildAndRender()
    {
        _items.Clear();
        using var dc = _content.RenderOpen();
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        if (Root == null || bounds.Width < 4 || bounds.Height < 4) return;

        double dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var top = CollectEntries(Root, true);
        int colorIdx = 0;

        Squarify(top, bounds, (k, r) =>
        {
            var e = top[k];
            int color = e.Node != null ? colorIdx++ : -1;
            var item = new TreemapItem
            {
                Node = e.Node, Owner = Root, FilePath = e.FilePath, Label = e.Label, Size = e.Size,
                Rect = r, Depth = 0, Color = color, IsFileGroup = e.IsGroup,
            };
            _items.Add(item);
            DrawCell(dc, item, dpi);

            // Cấp 2: vẽ các thư mục con bên trong nếu đủ chỗ
            if (e.Node != null && r.Width >= 70 && r.Height >= 50 && (e.Node.Children.Length > 0))
            {
                var inner = new Rect(r.X + 3, r.Y + 20, r.Width - 6, r.Height - 23);
                if (inner.Width > 8 && inner.Height > 8)
                {
                    var sub = CollectEntries(e.Node, false);
                    Squarify(sub, inner, (k2, r2) =>
                    {
                        var s = sub[k2];
                        var it2 = new TreemapItem
                        {
                            Node = s.Node, Owner = e.Node, Label = s.Label, Size = s.Size,
                            Rect = r2, Depth = 1, Color = s.Node != null ? color : -1, IsFileGroup = s.IsGroup,
                        };
                        _items.Add(it2);
                        DrawCell(dc, it2, dpi);
                    });
                }
            }
        });
    }

    private void DrawCell(DrawingContext dc, TreemapItem it, double dpi)
    {
        var r = it.Rect;
        if (r.Width < 0.6 || r.Height < 0.6) return;
        dc.DrawRectangle(GetBrush(it.Color, it.Depth), r.Width > 3 && r.Height > 3 ? BorderPen : null, r);

        bool hasNested = it.Depth == 0 && it.Node != null && r.Width >= 70 && r.Height >= 50 && it.Node.Children.Length > 0;
        if (hasNested)
            dc.DrawRectangle(HeaderBrush, null, new Rect(r.X, r.Y, r.Width, Math.Min(20, r.Height)));

        if (r.Width < 44 || r.Height < 16) return;

        dc.PushClip(new RectangleGeometry(new Rect(r.X + 2, r.Y, r.Width - 4, r.Height)));
        double fs = it.Depth == 0 ? 12 : 11;
        var name = new FormattedText(it.Label, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, Face, fs, Brushes.White, dpi)
        { MaxLineCount = 1, Trimming = TextTrimming.CharacterEllipsis, MaxTextWidth = Math.Max(1, r.Width - 8) };
        string sizeText = FileOps.FormatSize(it.Size);

        if (hasNested)
        {
            var sz = new FormattedText(sizeText, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, FaceLight, 11, Brushes.White, dpi);
            name.MaxTextWidth = Math.Max(1, r.Width - sz.Width - 16);
            dc.DrawText(name, new Point(r.X + 5, r.Y + 2));
            if (r.Width > sz.Width + 60) dc.DrawText(sz, new Point(r.Right - sz.Width - 5, r.Y + 3));
        }
        else
        {
            dc.DrawText(name, new Point(r.X + 4, r.Y + 3));
            if (r.Height >= 34)
            {
                var sz = new FormattedText(sizeText, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, FaceLight, fs - 1, Brushes.White, dpi);
                dc.DrawText(sz, new Point(r.X + 4, r.Y + 3 + fs + 4));
            }
        }
        dc.Pop();
    }

    private void RenderOverlay()
    {
        using var dc = _overlay.RenderOpen();
        if (_hover == null) return;
        var r = _hover.Rect;
        r.Inflate(-1, -1);
        if (r.Width <= 0 || r.Height <= 0) return;
        dc.DrawRectangle(HoverFill, HoverPenOuter, r);
        dc.DrawRectangle(null, HoverPen, r);
    }

    // ---------------- Chuột ----------------

    private TreemapItem? HitTest(Point p)
    {
        for (int i = _items.Count - 1; i >= 0; i--)
            if (_items[i].Rect.Contains(p) && _items[i].Rect.Width >= 0.6 && _items[i].Rect.Height >= 0.6) return _items[i];
        return null;
    }

    protected override HitTestResult? HitTestCore(PointHitTestParameters hitTestParameters) =>
        new PointHitTestResult(this, hitTestParameters.HitPoint);

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var hit = HitTest(e.GetPosition(this));
        if (!ReferenceEquals(hit, _hover))
        {
            _hover = hit;
            RenderOverlay();
            HoverChanged?.Invoke(hit);
        }
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        _hover = null;
        RenderOverlay();
        HoverChanged?.Invoke(null);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        var hit = HitTest(e.GetPosition(this));
        if (hit == null) return;
        if (e.ClickCount >= 2) ItemDoubleClicked?.Invoke(hit);
        else ItemClicked?.Invoke(hit);
    }

    protected override void OnMouseRightButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseRightButtonDown(e);
        var hit = HitTest(e.GetPosition(this));
        if (hit != null) ItemClicked?.Invoke(hit);
    }
}
