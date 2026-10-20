using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Diskat.Core;
using PdfSharp.Drawing;
using PdfSharp.Pdf;

namespace Diskat.UI;

/// <summary>Change / IsNew: chỉ có khi đang so sánh với một lần quét đã lưu.</summary>
public sealed record ReportFolder(string Name, long Size, long Files, bool Blocked, bool IsOwnFiles, long? Change = null, bool IsNew = false);
public sealed record ReportFile(string Name, string Folder, long Size, DateTime LastWriteUtc);

/// <summary>Ảnh chụp số liệu tại thời điểm xuất (lấy trên luồng giao diện, rồi dựng PDF ở luồng nền).</summary>
public sealed record ReportData(
    string RootPath,
    DateTime ScannedLocal,
    double ScanSeconds,
    bool ScanStopped,
    long TotalSize,
    long Files,
    long Folders,
    int Blocked,
    bool StatsStale,
    string? DriveName,
    long DriveTotal,
    long DriveFree,
    BitmapSource? Treemap,
    BitmapSource? Logo,
    IReadOnlyList<ReportFolder> TopFolders,
    IReadOnlyList<ReportFile> TopFiles,
    IReadOnlyList<TypeStat> Types,
    IReadOnlyList<AgeStat> Ages,
    string Version,
    // Tóm tắt thay đổi so với lần quét đang so sánh ("Tăng 3.2 GB so với lần quét lúc ..."), null nếu không so sánh
    string? Compare = null);

/// <summary>Báo cáo phân tích dung lượng dạng PDF (A4), dựng bằng PDFsharp.</summary>
public static class PdfReport
{
    private const double PageW = 595.28, PageH = 841.89, Margin = 40, ContentW = PageW - 2 * Margin;
    private const double FooterH = 28;

    private static readonly XColor Accent = XColor.FromArgb(0x2F, 0x6F, 0xED);
    private static readonly XColor AccentSoft = XColor.FromArgb(0xE8, 0xF0, 0xFE);
    private static readonly XColor Ink = XColor.FromArgb(0x1F, 0x24, 0x30);
    private static readonly XColor Sub = XColor.FromArgb(0x6B, 0x72, 0x80);
    private static readonly XColor Line = XColor.FromArgb(0xE3, 0xE7, 0xEE);
    private static readonly XColor Card = XColor.FromArgb(0xF5, 0xF7, 0xFA);
    private static readonly XColor Warn = XColor.FromArgb(0xFF, 0xF4, 0xDD);
    private static readonly XColor WarnInk = XColor.FromArgb(0x8A, 0x5A, 0x00);
    // Cột "Thay đổi": giống GrowText / ShrinkText của giao diện sáng
    private static readonly XColor GrowInk = XColor.FromArgb(0xB4, 0x38, 0x0F);
    private static readonly XColor ShrinkInk = XColor.FromArgb(0x14, 0x6C, 0x36);

    // Màu nhóm tuổi file: mới (xanh) đến cũ (cam đất)
    private static readonly XColor[] AgeColors =
    [
        XColor.FromArgb(0x2F, 0x6F, 0xED), XColor.FromArgb(0x2E, 0xA8, 0xD6), XColor.FromArgb(0x2F, 0xB5, 0x9C),
        XColor.FromArgb(0xA3, 0xB8, 0x35), XColor.FromArgb(0xF2, 0xB1, 0x2E), XColor.FromArgb(0xF0, 0x7F, 0x3C),
    ];

    public static void Save(ReportData data, string path)
    {
        PdfFonts.Install();
        var doc = new PdfDocument();
        doc.Info.Title = Loc.T("PdfTitle") + " - " + data.RootPath;
        doc.Info.Creator = "Diskat " + data.Version;
        doc.Info.Subject = data.RootPath;

        var w = new Writer(doc, data);
        w.Build();
        w.FinishFooters();
        doc.Save(path);
    }

    private sealed class Writer(PdfDocument doc, ReportData d)
    {
        private readonly List<PdfPage> _pages = new();
        private XGraphics _g = null!;
        private XImage? _logo;
        private double _y;
        private readonly Dictionary<(string, double, bool), XFont> _fonts = new();

        // ---------------- Trang và chữ ----------------

        private void NewPage()
        {
            _g?.Dispose();
            var page = doc.AddPage();
            page.Width = XUnit.FromPoint(PageW);
            page.Height = XUnit.FromPoint(PageH);
            _pages.Add(page);
            _g = XGraphics.FromPdfPage(page);
            _y = Margin;
            DrawHeader();
        }

        private void Ensure(double height)
        {
            if (_y + height > PageH - Margin - FooterH) NewPage();
        }

        // PDF không tự thay font khi thiếu ký tự như trên màn hình, nên chữ được chia thành từng đoạn:
        // ký tự CJK dùng font CJK, phần còn lại dùng Segoe UI. Nhờ vậy dấu "\" trong đường dẫn không bị
        // font Hàn / Nhật vẽ thành ₩ / ¥, và chữ Latin trông giống nhau trong mọi ngôn ngữ.

        private static bool IsHangul(char c) => c is >= '가' and <= '힯' or >= 'ᄀ' and <= 'ᇿ' or >= '㄰' and <= '㆏';
        private static bool IsKana(char c) => c is >= '぀' and <= 'ヿ' or >= 'ㇰ' and <= 'ㇿ';
        private static bool IsCjk(char c) => IsHangul(c) || IsKana(c) ||
            c is >= '㐀' and <= '鿿' or >= '豈' and <= '﫿' or >= '　' and <= '〿' or >= '＀' and <= '￯';

        /// <summary>Font CJK cho cả chuỗi: Hàn nếu có Hangul, Nhật nếu có Kana, còn lại theo ngôn ngữ giao diện.</summary>
        private static string CjkFamily(string s)
        {
            foreach (char c in s)
            {
                if (IsHangul(c)) return PdfFonts.Korean;
                if (IsKana(c)) return PdfFonts.Japanese;
            }
            return Loc.Lang switch { "ja" => PdfFonts.Japanese, "ko" => PdfFonts.Korean, _ => PdfFonts.Chinese };
        }

        private XFont Font(string family, double size, bool bold)
        {
            // Máy thiếu font CJK: vẫn xuất được báo cáo, chỉ các ký tự đó hiện thành ô trống
            if (!PdfFonts.IsAvailable(family)) family = PdfFonts.Latin;
            if (_fonts.TryGetValue((family, size, bold), out var f)) return f;
            f = new XFont(family, size, bold ? XFontStyleEx.Bold : XFontStyleEx.Regular, new XPdfFontOptions(PdfFontEncoding.Unicode));
            _fonts[(family, size, bold)] = f;
            return f;
        }

        /// <summary>Font cho một ký tự: font ưu tiên nếu có hình cho nó, nếu không thì font dự phòng đầu tiên có.</summary>
        private static string FamilyFor(int cp, Func<string> preferredCjk)
        {
            bool cjk = cp <= char.MaxValue && IsCjk((char)cp);
            if (!cjk)
            {
                if (cp < 0x250 || PdfFonts.Covers(PdfFonts.Latin, cp)) return PdfFonts.Latin;
                foreach (var f in PdfFonts.OtherFallbacks) if (PdfFonts.Covers(f, cp)) return f;
                return PdfFonts.Latin;
            }
            var pref = preferredCjk();
            if (PdfFonts.Covers(pref, cp)) return pref;
            // Vd. chữ Hán giản thể (载, 压) không có trong font Nhật / Hàn
            foreach (var f in PdfFonts.CjkFallbacks) if (PdfFonts.Covers(f, cp)) return f;
            return pref;
        }

        private List<(string Text, XFont Font)> Runs(string s, double size, bool bold)
        {
            var runs = new List<(string, XFont)>();
            string? cjk = null;
            string Preferred() => cjk ??= CjkFamily(s);
            string? curFamily = null;
            int start = 0, i = 0;
            while (i < s.Length)
            {
                // Đi theo từng code point để không tách đôi cặp surrogate (emoji, chữ hiếm)
                int len = char.IsHighSurrogate(s[i]) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1]) ? 2 : 1;
                int cp = len == 2 ? char.ConvertToUtf32(s[i], s[i + 1]) : s[i];
                // Khoảng trắng và dấu câu ASCII đi cùng đoạn trước, tránh cắt vụn đoạn chữ CJK
                string family = cp == ' ' && curFamily != null ? curFamily : FamilyFor(cp, Preferred);
                if (curFamily != null && family != curFamily)
                {
                    runs.Add((s[start..i], Font(curFamily, size, bold)));
                    start = i;
                }
                curFamily = family;
                i += len;
            }
            if (curFamily != null) runs.Add((s[start..], Font(curFamily, size, bold)));
            return runs;
        }

        private double Measure(string s, double size, bool bold)
        {
            double w = 0;
            foreach (var (text, font) in Runs(s, size, bold)) w += _g.MeasureString(text, font).Width;
            return w;
        }

        /// <summary>Vẽ theo đường chân chữ để các đoạn khác font thẳng hàng; y là mép trên của dòng.</summary>
        private void Draw(string s, double x, double y, double size, XColor color, bool bold)
        {
            var brush = new XSolidBrush(color);
            double baseline = y + size * 1.08;
            foreach (var (text, font) in Runs(s, size, bold))
            {
                _g.DrawString(text, font, brush, x, baseline);
                x += _g.MeasureString(text, font).Width;
            }
        }

        private double Text(string s, double x, double y, double size, XColor color, bool bold = false, double maxWidth = 0,
            bool right = false, bool middleEllipsis = false)
        {
            if (maxWidth > 0) s = middleEllipsis ? FitMiddle(s, size, bold, maxWidth) : Fit(s, size, bold, maxWidth);
            double w = Measure(s, size, bold);
            Draw(s, right ? x - w : x, y, size, color, bold);
            return w;
        }

        private string Fit(string s, double size, bool bold, double width)
        {
            if (Measure(s, size, bold) <= width) return s;
            int lo = 0, hi = s.Length;
            while (lo < hi)
            {
                int mid = (lo + hi + 1) / 2;
                if (Measure(s[..mid] + "…", size, bold) <= width) lo = mid; else hi = mid - 1;
            }
            return s[..lo] + "…";
        }

        /// <summary>Cắt ở giữa để giữ cả đầu và cuối đường dẫn (ổ đĩa và thư mục cuối).</summary>
        private string FitMiddle(string s, double size, bool bold, double width)
        {
            if (Measure(s, size, bold) <= width) return s;
            int lo = 0, hi = s.Length;
            while (lo < hi)
            {
                int mid = (lo + hi + 1) / 2;
                int head = mid / 2, tail = mid - head;
                if (Measure(s[..head] + "…" + s[^tail..], size, bold) <= width) lo = mid; else hi = mid - 1;
            }
            int h2 = lo / 2, t2 = lo - h2;
            return s[..h2] + "…" + s[^t2..];
        }

        /// <summary>
        /// Chia đoạn văn thành dòng. Chữ CJK không dùng khoảng trắng giữa các từ nên được phép xuống dòng
        /// giữa hai ký tự CJK bất kỳ; chữ Latin chỉ xuống dòng ở khoảng trắng.
        /// </summary>
        private List<string> Wrap(string s, double width, double size)
        {
            var lines = new List<string>();
            foreach (var para in s.Split('\n'))
            {
                var tokens = new List<string>();
                int i = 0;
                while (i < para.Length)
                {
                    int j = i + 1;
                    if (para[i] == ' ') while (j < para.Length && para[j] == ' ') j++;
                    else if (!IsCjk(para[i])) while (j < para.Length && para[j] != ' ' && !IsCjk(para[j])) j++;
                    tokens.Add(para[i..j]);
                    i = j;
                }
                var line = "";
                foreach (var t in tokens)
                {
                    if (line.Length > 0 && Measure(line + t, size, false) > width && t != " ")
                    {
                        lines.Add(line.TrimEnd());
                        line = t.TrimStart();
                    }
                    else line += t;
                }
                lines.Add(line.TrimEnd());
            }
            return lines;
        }

        private static double LineHeight(double size) => size * 1.45;

        /// <summary>Vẽ đoạn văn có xuống dòng, trả về chiều cao đã dùng.</summary>
        private double Paragraph(string s, double x, double y, double width, double size, XColor color)
        {
            var lines = Wrap(s, width, size);
            for (int i = 0; i < lines.Count; i++) Draw(lines[i], x, y + i * LineHeight(size), size, color, false);
            return lines.Count * LineHeight(size);
        }

        private void Rect(double x, double y, double w, double h, XColor color, double radius = 0)
        {
            if (w <= 0 || h <= 0) return;
            var b = new XSolidBrush(color);
            if (radius > 0) _g.DrawRoundedRectangle(b, new XRect(x, y, w, h), new XSize(radius * 2, radius * 2));
            else _g.DrawRectangle(b, new XRect(x, y, w, h));
        }

        private void HLine(double y, XColor color, double width = 0.75) =>
            _g.DrawLine(new XPen(color, width), Margin, y, PageW - Margin, y);

        private static string Count(long n) => FileOps.FormatCount(n);
        private static string Size(long n) => FileOps.FormatSize(n);
        private static string Pct(double p) => p >= 10 ? p.ToString("0", CultureInfo.InvariantCulture) + "%"
                                              : p.ToString("0.0", CultureInfo.InvariantCulture) + "%";

        // ---------------- Nội dung ----------------

        public void Build()
        {
            NewPage();
            Summary();
            Treemap();
            Folders();
            Files();
            Types();
            Ages();
            Notes();
        }

        private void DrawHeader()
        {
            double x = Margin;
            if (d.Logo != null)
            {
                _logo ??= XImage.FromBitmapSource(d.Logo);
                _g.DrawImage(_logo, new XRect(x, _y - 2, 18, 18));
                x += 24;
            }
            Text("Diskat", x, _y, 11, Ink, bold: true);
            Text(Loc.T("PdfTitle"), PageW - Margin, _y + 1, 9, Sub, right: true);
            _y += 22;
            HLine(_y, Line);
            _y += 18;
        }

        private void Summary()
        {
            string name = d.RootPath.Length <= 3 ? d.RootPath : Path.GetFileName(d.RootPath.TrimEnd('\\'));
            Text(name, Margin, _y, 22, Ink, bold: true, maxWidth: ContentW);
            _y += 31;
            Text(d.RootPath, Margin, _y, 9.5, Sub, maxWidth: ContentW, middleEllipsis: true);
            _y += 15;
            string when = d.ScannedLocal.ToString(Loc.T("DateFormat"), CultureInfo.InvariantCulture);
            Text(Loc.F("PdfScanned", when, d.ScanSeconds), Margin, _y, 9.5, Sub, maxWidth: ContentW);
            if (d.Compare != null)
            {
                _y += 15;
                Text(d.Compare, Margin, _y, 9.5, Accent, bold: true, maxWidth: ContentW);
            }
            _y += 24;

            var cards = new List<(string Label, string Value, string? Note)>
            {
                (Loc.T("PdfTotal"), Size(d.TotalSize), null),
                (Loc.T("PdfFiles"), Count(d.Files), null),
                (Loc.T("PdfFolders"), Count(d.Folders), null),
            };
            if (d.DriveName != null && d.DriveTotal > 0)
                cards.Add((Loc.F("PdfFree", d.DriveName), Size(d.DriveFree), Loc.F("PdfFreeOf", Size(d.DriveTotal))));

            const double gap = 10, h = 58;
            double cw = (ContentW - gap * (cards.Count - 1)) / cards.Count;
            for (int i = 0; i < cards.Count; i++)
            {
                double x = Margin + i * (cw + gap);
                Rect(x, _y, cw, h, Card, 6);
                // Ghi chú (vd. "of 476 GB") nằm cùng dòng nhãn, canh phải, để số lớn có đủ chỗ
                double noteW = cards[i].Note is { } note ? Text(note, x + cw - 12, _y + 10, 7.5, Sub, right: true) + 6 : 0;
                Text(cards[i].Label.ToUpper(CultureInfo.CurrentCulture), x + 12, _y + 10, 7.5, Sub, bold: true, maxWidth: cw - 24 - noteW);
                Text(cards[i].Value, x + 12, _y + 24, 17, Ink, bold: true, maxWidth: cw - 24);
            }
            _y += h + 12;

            // Cảnh báo số liệu thiếu
            var warnings = new List<string>();
            if (d.ScanStopped) warnings.Add(Loc.T("PdfStopped"));
            if (d.Blocked > 0) warnings.Add(Loc.F("PdfIncomplete", Count(d.Blocked)));
            foreach (var wtext in warnings)
            {
                double bh = Wrap(wtext, ContentW - 24, 9).Count * LineHeight(9) + 16;
                Rect(Margin, _y, ContentW, bh, Warn, 6);
                Paragraph(wtext, Margin + 12, _y + 8, ContentW - 24, 9, WarnInk);
                _y += bh + 8;
            }
            _y += 6;
        }

        private void SectionTitle(string title, double needBelow)
        {
            Ensure(30 + needBelow);
            Text(title, Margin, _y, 13, Ink, bold: true);
            _y += 22;
        }

        private void Treemap()
        {
            if (d.Treemap == null) return;
            double h = ContentW * d.Treemap.PixelHeight / Math.Max(1, d.Treemap.PixelWidth);
            SectionTitle(Loc.T("PdfMap"), h);
            _g.DrawImage(XImage.FromBitmapSource(d.Treemap), new XRect(Margin, _y, ContentW, h));
            _y += h + 22;
        }

        // Cột bảng: vị trí x và độ rộng
        private void TableHeader(params (string Text, double X, double W, bool Right)[] cols)
        {
            foreach (var c in cols)
            {
                var t = c.Text.ToUpper(CultureInfo.CurrentCulture);
                if (c.Right) Text(t, c.X + c.W, _y, 7.5, Sub, bold: true, right: true);
                else Text(t, c.X, _y, 7.5, Sub, bold: true, maxWidth: c.W);
            }
            _y += 13;
            HLine(_y, Line);
            _y += 5;
        }

        private void ShareBar(double x, double y, double w, double pct, XColor color)
        {
            Rect(x, y, w, 5, AccentSoft, 2.5);
            Rect(x, y, Math.Max(1.5, w * Math.Clamp(pct, 0, 100) / 100), 5, color, 2.5);
        }

        private void Folders()
        {
            if (d.TopFolders.Count == 0) return;
            SectionTitle(Loc.T("PdfTopFolders"), 18 * 3 + 18);
            // Đang so sánh với lần quét trước: thêm cột Thay đổi, thu hẹp cột tên và thanh tỉ lệ
            bool cmp = d.Compare != null;
            double nameW = cmp ? 190 : 262, barW = cmp ? 64 : 80;
            double xNum = Margin, xName = Margin + 18, xBar = xName + nameW + 10, xPct = xBar + barW + 35, xSize = xPct + 60,
                xChange = xSize + 70, xFiles = PageW - Margin;
            void Head()
            {
                var cols = new List<(string, double, double, bool)>
                {
                    ("#", xNum, 16, false), (Loc.T("PdfColName"), xName, nameW, false),
                    (Loc.T("PdfColShare"), xBar, barW, false), (Loc.T("PdfColSize"), xSize - 60, 60, true),
                };
                if (cmp) cols.Add((Loc.T("ColChange"), xChange - 60, 60, true));
                cols.Add((Loc.T("PdfColFiles"), xFiles - 60, 60, true));
                TableHeader(cols.ToArray());
            }
            Head();
            int i = 0;
            foreach (var f in d.TopFolders)
            {
                if (_y + 18 > PageH - Margin - FooterH) { NewPage(); Head(); }
                i++;
                double pct = d.TotalSize > 0 ? f.Size * 100.0 / d.TotalSize : 0;
                Text(i.ToString(CultureInfo.InvariantCulture), xNum, _y, 9, Sub);
                string label = f.IsOwnFiles ? Loc.T("PdfOwnFiles") : f.Name;
                double nw = Text(label, xName, _y, 9.5, f.IsOwnFiles ? Sub : Ink, bold: !f.IsOwnFiles, maxWidth: nameW);
                if (f.Blocked) Text("  " + Loc.T("PdfBlocked"), xName + nw, _y + 1, 8, WarnInk, maxWidth: Math.Max(1, nameW - nw));
                else if (f.IsNew) Text("  " + Loc.T("CompareNew"), xName + nw, _y + 1, 8, Accent, bold: true, maxWidth: Math.Max(1, nameW - nw));
                ShareBar(xBar, _y + 4.5, barW, pct, Accent);
                Text(Pct(pct), xPct, _y, 8.5, Sub, right: true);
                Text(Size(f.Size), xSize, _y, 9.5, Ink, bold: true, right: true);
                if (cmp && f.Change is long ch && (ch != 0 || f.IsNew))
                    Text((ch < 0 ? "-" : "+") + Size(Math.Abs(ch)), xChange, _y, 9, ch < 0 ? ShrinkInk : GrowInk, bold: true, right: true);
                Text(Count(f.Files), xFiles, _y, 9, Sub, right: true);
                _y += 18;
            }
            _y += 16;
        }

        private void Files()
        {
            if (d.TopFiles.Count == 0) return;
            SectionTitle(Loc.T("PdfTopFiles"), 18 * 3 + 18);
            double xName = Margin, xFolder = Margin + 190, xMod = Margin + 390, xSize = PageW - Margin;
            void Head() => TableHeader((Loc.T("PdfColName"), xName, 180, false), (Loc.T("PdfColFolder"), xFolder, 190, false),
                (Loc.T("PdfColModified"), xMod, 80, false), (Loc.T("PdfColSize"), xSize - 60, 60, true));
            Head();
            foreach (var f in d.TopFiles)
            {
                if (_y + 17 > PageH - Margin - FooterH) { NewPage(); Head(); }
                Text(f.Name, xName, _y, 9, Ink, bold: true, maxWidth: 182);
                Text(f.Folder, xFolder, _y, 8.5, Sub, maxWidth: 192, middleEllipsis: true);
                string mod = f.LastWriteUtc.Year < 1980 ? "" :
                    f.LastWriteUtc.ToLocalTime().ToString(Loc.T("DateFormat"), CultureInfo.InvariantCulture);
                Text(mod, xMod, _y, 8.5, Sub, maxWidth: 80);
                Text(Size(f.Size), xSize, _y, 9, Ink, bold: true, right: true);
                _y += 17;
            }
            _y += 16;
        }

        private void Types()
        {
            if (d.Types.Count == 0) return;
            const int shown = 14;
            var rows = d.Types.Take(shown).Select(t => (Label: t.Extension.Length == 0 ? Loc.T("PdfNoExt") : t.Extension, t.Size, t.Count)).ToList();
            if (d.Types.Count > shown)
            {
                var rest = d.Types.Skip(shown).ToList();
                rows.Add((Loc.F("PdfOtherTypes", Count(rest.Count)), rest.Sum(t => t.Size), rest.Sum(t => t.Count)));
            }
            long total = d.Types.Sum(t => t.Size);

            SectionTitle(Loc.T("PdfTypes"), 18 * 3 + 18);
            double xType = Margin, xBar = Margin + 150, xPct = Margin + 385, xFiles = Margin + 450, xSize = PageW - Margin;
            void Head() => TableHeader((Loc.T("PdfColType"), xType, 140, false), (Loc.T("PdfColShare"), xBar, 200, false),
                (Loc.T("PdfColFiles"), xFiles - 60, 60, true), (Loc.T("PdfColSize"), xSize - 60, 60, true));
            Head();
            foreach (var r in rows)
            {
                if (_y + 17 > PageH - Margin - FooterH) { NewPage(); Head(); }
                double pct = total > 0 ? r.Size * 100.0 / total : 0;
                Text(r.Label, xType, _y, 9.5, Ink, bold: true, maxWidth: 140);
                ShareBar(xBar, _y + 4.5, 200, pct, Accent);
                Text(Pct(pct), xPct, _y, 8.5, Sub, right: true);
                Text(Count(r.Count), xFiles, _y, 9, Sub, right: true);
                Text(Size(r.Size), xSize, _y, 9.5, Ink, bold: true, right: true);
                _y += 17;
            }
            _y += 16;
        }

        private void Ages()
        {
            long total = d.Ages.Sum(a => a.Size);
            if (total <= 0) return;
            SectionTitle(Loc.T("PdfAges"), 44 + d.Ages.Count * 17);

            // Thanh xếp chồng: cả cây theo tuổi file
            double x = Margin;
            for (int i = 0; i < d.Ages.Count; i++)
            {
                double w = ContentW * d.Ages[i].Size / total;
                Rect(x, _y, w, 12, AgeColors[i % AgeColors.Length]);
                x += w;
            }
            _y += 22;

            double xPct = Margin + 330, xFiles = Margin + 430, xSize = PageW - Margin;
            TableHeader((Loc.T("PdfColModified"), Margin, 200, false), (Loc.T("PdfColShare"), xPct - 60, 60, true),
                (Loc.T("PdfColFiles"), xFiles - 60, 60, true), (Loc.T("PdfColSize"), xSize - 60, 60, true));
            for (int i = 0; i < d.Ages.Count; i++)
            {
                var a = d.Ages[i];
                Rect(Margin, _y + 3, 8, 8, AgeColors[i % AgeColors.Length], 2);
                Text(AgeLabel(i, d.Ages.Count), Margin + 16, _y, 9.5, Ink, maxWidth: 200);
                Text(Pct(a.Size * 100.0 / total), xPct, _y, 8.5, Sub, right: true);
                Text(Count(a.Count), xFiles, _y, 9, Sub, right: true);
                Text(Size(a.Size), xSize, _y, 9.5, Ink, bold: true, right: true);
                _y += 17;
            }
            _y += 16;
        }

        private static string AgeLabel(int i, int n) => Loc.T("Age" + Math.Min(i, n - 1));

        private void Notes()
        {
            if (!d.StatsStale) return;
            string note = Loc.T("PdfStale");
            Ensure(40);
            _y += Paragraph(note, Margin, _y, ContentW, 8.5, Sub) + 6;
        }

        public void FinishFooters()
        {
            _g?.Dispose();
            int n = _pages.Count;
            for (int i = 0; i < n; i++)
            {
                using var g = XGraphics.FromPdfPage(_pages[i], XGraphicsPdfPageOptions.Append);
                _g = g;
                double y = PageH - Margin - 10;
                HLine(y - 6, Line);
                Text("Diskat " + d.Version + "  ·  diskat.cc", Margin, y, 8, Sub);
                Text(Loc.F("PdfPage", i + 1, n), PageW - Margin, y, 8, Sub, right: true);
            }
        }
    }

    // ---------------- Hình ảnh (luồng giao diện) ----------------

    /// <summary>Vẽ bản đồ dung lượng ngoài màn hình, độ phân giải gấp đôi để in rõ. Báo cáo luôn dùng màu sáng.</summary>
    public static BitmapSource RenderTreemap(DirNode root, double width, double height)
    {
        var map = new TreemapControl { AlwaysLight = true };
        map.Measure(new Size(width, height));
        map.Arrange(new Rect(0, 0, width, height));
        map.SetRoot(root);
        var bmp = new RenderTargetBitmap((int)(width * 2), (int)(height * 2), 192, 192, PixelFormats.Pbgra32);
        bmp.Render(map);
        return Jpeg(bmp);
    }

    /// <summary>JPEG chất lượng cao: ảnh bản đồ nhỏ hơn nhiều so với ảnh không nén trong PDF.</summary>
    private static BitmapSource Jpeg(BitmapSource src)
    {
        // JPEG không có kênh alpha: phủ nền trắng trước
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, src.Width, src.Height));
            dc.DrawImage(src, new Rect(0, 0, src.Width, src.Height));
        }
        var flat = new RenderTargetBitmap(src.PixelWidth, src.PixelHeight, src.DpiX, src.DpiY, PixelFormats.Pbgra32);
        flat.Render(dv);

        var enc = new JpegBitmapEncoder { QualityLevel = 92 };
        enc.Frames.Add(BitmapFrame.Create(flat));
        var ms = new MemoryStream();
        enc.Save(ms);
        ms.Position = 0;
        var img = new BitmapImage();
        img.BeginInit();
        img.CacheOption = BitmapCacheOption.OnLoad;
        img.StreamSource = ms;
        img.EndInit();
        img.Freeze();
        return img;
    }

    public static BitmapSource? RenderLogo()
    {
        if (Application.Current.TryFindResource("LogoImage") is not ImageSource logo) return null;
        const int px = 96;
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen()) dc.DrawImage(logo, new Rect(0, 0, px, px));
        var bmp = new RenderTargetBitmap(px, px, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(dv);
        bmp.Freeze();
        return bmp;
    }
}
