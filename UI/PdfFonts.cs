using PdfSharp.Fonts;

namespace Diskat.UI;

/// <summary>
/// Lấy font trực tiếp từ thư mục Fonts của Windows cho PDF. Cần thiết cho font CJK: chúng nằm trong file
/// .ttc (nhiều font trong một file) mà PDFsharp không tự tìm ra theo tên.
/// </summary>
internal sealed class PdfFonts : IFontResolver
{
    public const string Latin = "Segoe UI";
    public const string Chinese = "Microsoft YaHei";
    public const string Japanese = "Yu Gothic";
    public const string Korean = "Malgun Gothic";
    public const string Symbol = "Segoe UI Symbol";

    /// <summary>Thứ tự thử khi font ưu tiên thiếu một ký tự.</summary>
    public static readonly string[] CjkFallbacks = [Chinese, Japanese, Korean];
    public static readonly string[] OtherFallbacks = [Symbol, Chinese, Japanese, Korean];

    private static readonly string FontDir = Environment.GetFolderPath(Environment.SpecialFolder.Fonts);

    // Họ font → (file thường, file đậm). Số thứ tự 0 trong .ttc là bản không có "UI" của họ font đó.
    private static readonly Dictionary<string, (string Regular, string Bold)> Files = new(StringComparer.OrdinalIgnoreCase)
    {
        [Latin] = ("segoeui.ttf", "segoeuib.ttf"),
        [Chinese] = ("msyh.ttc", "msyhbd.ttc"),
        [Japanese] = ("YuGothR.ttc", "YuGothB.ttc"),
        [Korean] = ("malgun.ttf", "malgunbd.ttf"),
        [Symbol] = ("seguisym.ttf", "seguisym.ttf"),
    };

    private static readonly Dictionary<string, IDictionary<int, ushort>?> CharMaps = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Font có hình cho ký tự này không (đọc bảng cmap qua WPF, lưu đệm theo họ font).</summary>
    public static bool Covers(string family, int codepoint)
    {
        lock (CharMaps)
        {
            if (!CharMaps.TryGetValue(family, out var map))
            {
                map = null;
                try
                {
                    var tf = new System.Windows.Media.Typeface(new System.Windows.Media.FontFamily(family),
                        System.Windows.FontStyles.Normal, System.Windows.FontWeights.Normal, System.Windows.FontStretches.Normal);
                    if (IsAvailable(family) && tf.TryGetGlyphTypeface(out var gt)) map = gt.CharacterToGlyphMap;
                }
                catch { }
                CharMaps[family] = map;
            }
            return map != null && map.ContainsKey(codepoint);
        }
    }

    private static readonly object Gate = new();
    private static bool _installed;

    public static void Install()
    {
        lock (Gate)
        {
            if (_installed) return;
            GlobalFontSettings.FontResolver = new PdfFonts();
            _installed = true;
        }
    }

    public static bool IsAvailable(string family) =>
        Files.TryGetValue(family, out var f) && File.Exists(Path.Combine(FontDir, f.Regular));

    public FontResolverInfo? ResolveTypeface(string familyName, bool bold, bool italic)
    {
        if (!Files.TryGetValue(familyName, out var f)) return null;
        string file = bold ? f.Bold : f.Regular;
        bool simulateBold = false;
        if (!File.Exists(Path.Combine(FontDir, file)))
        {
            if (!bold || !File.Exists(Path.Combine(FontDir, f.Regular))) return null;
            file = f.Regular;
            simulateBold = true;
        }
        return simulateBold
            ? new FontResolverInfo(file, PdfSharp.Drawing.XStyleSimulations.BoldSimulation)
            : new FontResolverInfo(file);
    }

    private static readonly Dictionary<string, byte[]> Cache = new(StringComparer.OrdinalIgnoreCase);

    public byte[]? GetFont(string faceName)
    {
        lock (Cache)
        {
            if (Cache.TryGetValue(faceName, out var cached)) return cached;
            try
            {
                var data = File.ReadAllBytes(Path.Combine(FontDir, faceName));
                if (IsCollection(data)) data = ExtractFromCollection(data, 0);
                Cache[faceName] = data;
                return data;
            }
            catch { return null; }
        }
    }

    // ---------------- Tách một font ra khỏi file .ttc ----------------

    private static bool IsCollection(byte[] d) => d.Length > 12 && d[0] == 't' && d[1] == 't' && d[2] == 'c' && d[3] == 'f';

    private static uint U32(byte[] d, int o) => (uint)(d[o] << 24 | d[o + 1] << 16 | d[o + 2] << 8 | d[o + 3]);
    private static ushort U16(byte[] d, int o) => (ushort)(d[o] << 8 | d[o + 1]);

    private static void Put32(byte[] d, int o, uint v)
    {
        d[o] = (byte)(v >> 24); d[o + 1] = (byte)(v >> 16); d[o + 2] = (byte)(v >> 8); d[o + 3] = (byte)v;
    }

    /// <summary>
    /// TTC = tiêu đề "ttcf" + bảng vị trí các font; mỗi font có bảng mục lục (offset table) trỏ tới các bảng dữ liệu
    /// theo vị trí tuyệt đối trong file. Dựng lại một file .ttf độc lập: mục lục mới + chép từng bảng, căn lề 4 byte.
    /// </summary>
    private static byte[] ExtractFromCollection(byte[] ttc, int index)
    {
        uint numFonts = U32(ttc, 8);
        if (index >= numFonts) throw new InvalidDataException("font index");
        int dir = (int)U32(ttc, 12 + 4 * index);
        int numTables = U16(ttc, dir + 4);
        int headerSize = 12 + 16 * numTables;

        long total = headerSize;
        for (int i = 0; i < numTables; i++)
            total += (U32(ttc, dir + 12 + 16 * i + 12) + 3) & ~3u;

        var ttf = new byte[total];
        Array.Copy(ttc, dir, ttf, 0, 12); // sfntVersion, numTables, searchRange, entrySelector, rangeShift
        int pos = headerSize;
        for (int i = 0; i < numTables; i++)
        {
            int rec = dir + 12 + 16 * i, outRec = 12 + 16 * i;
            Array.Copy(ttc, rec, ttf, outRec, 8); // tag + checksum
            int offset = (int)U32(ttc, rec + 8), length = (int)U32(ttc, rec + 12);
            Put32(ttf, outRec + 8, (uint)pos);
            Put32(ttf, outRec + 12, (uint)length);
            Array.Copy(ttc, offset, ttf, pos, length);
            pos += (length + 3) & ~3;
        }
        return ttf;
    }
}
