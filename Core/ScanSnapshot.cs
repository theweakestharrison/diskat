using System.Globalization;
using System.IO.Compression;
using System.Text;

namespace Diskat.Core;

/// <summary>Phần đầu của một lần quét đã lưu (đọc được mà không cần giải nén phần thân).</summary>
public sealed record SnapshotInfo(
    string FilePath,
    string RootPath,
    DateTime ScannedUtc,
    string AppVersion,
    long TotalSize,
    long FileCount,
    long DirCount,
    int NodeCount,
    int Errors);

/// <summary>
/// Lưu cây thư mục sau mỗi lần quét xong để so sánh về sau. Chỉ có thư mục, không có từng file:
/// tên, Size, FileCount, DirCount. Nằm ở %LOCALAPPDATA%\Diskat\snapshots\&lt;thư mục gốc&gt;\, không gửi đi đâu.
///
/// Định dạng, phiên bản 1:
///   "DSNP" | int32 phiên bản | phiên bản app | đường dẫn gốc | int64 lúc quét (UTC ticks)
///   | int64 Size, FileCount, DirCount của gốc | int32 số thư mục | int32 số thư mục lỗi
///   | phần thân nén GZip: mọi thư mục theo chiều rộng (BFS), mỗi thư mục gồm
///     tên (UTF-8, độ dài 7-bit, gốc để trống) | Size, FileCount, DirCount (7-bit) | cờ (byte) | số thư mục con (7-bit)
/// Duyệt theo chiều rộng nên các con của một thư mục nằm liền nhau: đọc lại thành mảng, không cần lưu con trỏ.
/// </summary>
public static class ScanSnapshot
{
    public const int FormatVersion = 1;
    /// <summary>Số lần quét giữ lại cho mỗi thư mục gốc (cũ hơn thì xóa).</summary>
    public const int KeepPerRoot = 10;
    private const string Extension = ".dsnap";
    private static ReadOnlySpan<byte> Magic => "DSNP"u8;

    internal const byte FlagUnreadable = 1, FlagLink = 2, FlagNotScanned = 4;

    public static string BaseFolder { get; set; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Diskat", "snapshots");

    public static string Normalize(string path)
    {
        var full = Path.GetFullPath(path);
        return full.Length > 3 ? full.TrimEnd('\\', '/') : full;
    }

    public static bool SameRoot(string a, string b) =>
        string.Equals(Normalize(a), Normalize(b), StringComparison.OrdinalIgnoreCase);

    /// <summary>Thư mục chứa các lần quét của một thư mục gốc: tên dễ nhận ra cộng mã băm của đường dẫn.</summary>
    public static string FolderFor(string rootPath)
    {
        string norm = Normalize(rootPath);
        string label = norm.Length <= 3 ? norm[..1] : Path.GetFileName(norm);
        var sb = new StringBuilder(label.Length);
        foreach (char c in label) sb.Append(char.IsLetterOrDigit(c) || c is '-' or '_' ? c : '_');
        if (sb.Length > 32) sb.Length = 32;
        return Path.Combine(BaseFolder, $"{sb}-{NameHash(norm):x16}");
    }

    /// <summary>FNV-1a 64 bit trên chữ hoa: tên thư mục trên Windows không phân biệt hoa thường.</summary>
    internal static ulong NameHash(ReadOnlySpan<char> s)
    {
        ulong h = 14695981039346656037;
        foreach (char c in s)
        {
            h ^= char.ToUpperInvariant(c);
            h *= 1099511628211;
        }
        return h;
    }

    // ================= Ghi =================

    /// <summary>
    /// Lưu cây vừa quét xong (gọi ở luồng nền) rồi xóa bớt các lần quét cũ của cùng thư mục gốc.
    /// Ghi ra file tạm rồi đổi tên, nên app bị đóng giữa chừng cũng không để lại file hỏng.
    /// </summary>
    public static SnapshotInfo Save(DirNode root, DateTime scannedUtc, int errors, string appVersion, int keep = KeepPerRoot)
    {
        string rootPath = Normalize(root.FullPath);
        string dir = FolderFor(rootPath);
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, scannedUtc.ToString("yyyyMMdd-HHmmss-fff", CultureInfo.InvariantCulture) + Extension);
        string tmp = path + ".tmp";

        long size = Interlocked.Read(ref root.Size), files = Interlocked.Read(ref root.FileCount), dirs = Interlocked.Read(ref root.DirCount);
        int count = 0;
        using (var fs = new FileStream(tmp, FileMode.Create, FileAccess.ReadWrite, FileShare.None, 1 << 16))
        {
            using var w = new BinaryWriter(fs, Encoding.UTF8, leaveOpen: true);
            w.Write(Magic);
            w.Write(FormatVersion);
            w.Write(appVersion);
            w.Write(rootPath);
            w.Write(scannedUtc.Ticks);
            w.Write(size);
            w.Write(files);
            w.Write(dirs);
            long countPos = fs.Position;
            w.Write(0);
            w.Write(errors);
            w.Flush();

            using (var body = new BinaryWriter(new BufferedStream(new GZipStream(fs, CompressionLevel.Optimal, leaveOpen: true), 1 << 16), Encoding.UTF8))
            {
                var queue = new Queue<DirNode>();
                queue.Enqueue(root);
                while (queue.TryDequeue(out var n))
                {
                    // Đọc danh sách con một lần: số con ghi ra và các con xếp hàng phải khớp nhau
                    // kể cả khi giao diện vừa xóa / quét lại một thư mục
                    var kids = n.Children;
                    body.Write(count == 0 ? "" : n.Name);
                    body.Write7BitEncodedInt64(Math.Max(0, Interlocked.Read(ref n.Size)));
                    body.Write7BitEncodedInt64(Math.Max(0, Interlocked.Read(ref n.FileCount)));
                    body.Write7BitEncodedInt64(Math.Max(0, Interlocked.Read(ref n.DirCount)));
                    byte flags = 0;
                    if (n.AccessDenied || n.BadName) flags |= FlagUnreadable;
                    if (n.IsLink) flags |= FlagLink;
                    if (!n.Scanned) flags |= FlagNotScanned;
                    body.Write(flags);
                    body.Write7BitEncodedInt(kids.Length);
                    foreach (var c in kids) queue.Enqueue(c);
                    count++;
                }
            }

            fs.Position = countPos;
            w.Write(count);
            w.Flush();
        }
        File.Move(tmp, path, overwrite: true);
        Prune(dir, keep);
        return new SnapshotInfo(path, rootPath, scannedUtc, appVersion, size, files, dirs, count, errors);
    }

    /// <summary>Giữ <paramref name="keep"/> lần quét mới nhất (tên file là thời điểm quét nên sắp theo tên là đủ).</summary>
    private static void Prune(string dir, int keep)
    {
        var di = new DirectoryInfo(dir);
        foreach (var f in di.GetFiles("*" + Extension).OrderByDescending(f => f.Name, StringComparer.Ordinal).Skip(keep))
            try { f.Delete(); } catch { }
        // File tạm sót lại khi app bị đóng lúc đang lưu
        foreach (var t in di.GetFiles("*" + Extension + ".tmp"))
            if (t.LastWriteTimeUtc < DateTime.UtcNow.AddHours(-1))
                try { t.Delete(); } catch { }
    }

    // ================= Đọc =================

    /// <summary>Các lần quét đã lưu của thư mục gốc này, mới nhất trước.</summary>
    public static List<SnapshotInfo> List(string rootPath)
    {
        var result = new List<SnapshotInfo>();
        string dir = FolderFor(rootPath);
        if (!Directory.Exists(dir)) return result;
        foreach (var f in Directory.EnumerateFiles(dir, "*" + Extension))
            if (ReadInfo(f) is { } info && SameRoot(info.RootPath, rootPath))
                result.Add(info);
        result.Sort((a, b) => b.ScannedUtc.CompareTo(a.ScannedUtc));
        return result;
    }

    public static SnapshotInfo? ReadInfo(string file)
    {
        try
        {
            using var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, 4096);
            using var r = new BinaryReader(fs, Encoding.UTF8);
            return ReadInfo(r, file);
        }
        catch { return null; }
    }

    internal static SnapshotInfo? ReadInfo(BinaryReader r, string file)
    {
        Span<byte> magic = stackalloc byte[4];
        if (r.Read(magic) != 4 || !magic.SequenceEqual(Magic)) return null;
        // Phiên bản định dạng mới hơn (từ bản Diskat sau này): bỏ qua thay vì đọc sai
        if (r.ReadInt32() != FormatVersion) return null;
        string version = r.ReadString();
        string root = r.ReadString();
        var when = new DateTime(r.ReadInt64(), DateTimeKind.Utc);
        long size = r.ReadInt64(), files = r.ReadInt64(), dirs = r.ReadInt64();
        int count = r.ReadInt32(), errors = r.ReadInt32();
        return count > 0 ? new SnapshotInfo(file, root, when, version, size, files, dirs, count, errors) : null;
    }

    /// <summary>Tổng số lần quét đã lưu (mọi thư mục gốc) và dung lượng chúng chiếm.</summary>
    public static (int Count, long Bytes) Usage()
    {
        if (!Directory.Exists(BaseFolder)) return (0, 0);
        int n = 0;
        long bytes = 0;
        foreach (var f in new DirectoryInfo(BaseFolder).EnumerateFiles("*" + Extension, SearchOption.AllDirectories))
        {
            n++;
            bytes += f.Length;
        }
        return (n, bytes);
    }

    /// <summary>Xóa mọi lần quét đã lưu. Trả về số file đã xóa.</summary>
    public static int DeleteAll()
    {
        if (!Directory.Exists(BaseFolder)) return 0;
        int n = 0;
        foreach (var f in new DirectoryInfo(BaseFolder).EnumerateFiles("*", SearchOption.AllDirectories))
        {
            try { f.Delete(); if (f.Name.EndsWith(Extension, StringComparison.OrdinalIgnoreCase)) n++; } catch { }
        }
        foreach (var d in new DirectoryInfo(BaseFolder).EnumerateDirectories())
            try { d.Delete(false); } catch { }
        return n;
    }
}

/// <summary>
/// So cây đang hiển thị với một lần quét đã lưu. Lần quét cũ được nạp thành các mảng gọn (khoảng 36 byte
/// mỗi thư mục, không giữ tên mà chỉ giữ mã băm tên), rồi mỗi thư mục hiện tại được dò theo tên từ gốc xuống,
/// chỉ khi cần (khi dòng đó hiện ra) và nhớ lại kết quả.
/// </summary>
public sealed class ScanComparison
{
    public SnapshotInfo Info { get; }
    public DirNode Root { get; }

    private readonly long[] _size;
    private readonly long[] _files;
    // Con của thư mục i là các vị trí _first[i] .. _first[i] + _count[i] - 1
    private readonly int[] _first;
    private readonly int[] _count;
    // Trong khoảng con của mỗi thư mục: mã băm tên đã sắp xếp, và thư mục ứng với từng vị trí
    private readonly ulong[] _hash;
    private readonly int[] _index;
    private readonly Dictionary<DirNode, int> _found = new();

    private ScanComparison(SnapshotInfo info, DirNode root, int n)
    {
        Info = info;
        Root = root;
        _size = new long[n];
        _files = new long[n];
        _first = new int[n];
        _count = new int[n];
        _hash = new ulong[n];
        _index = new int[n];
    }

    public static ScanComparison Load(string file, DirNode root)
    {
        using var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16);
        using var head = new BinaryReader(fs, Encoding.UTF8, leaveOpen: true);
        var info = ScanSnapshot.ReadInfo(head, file) ?? throw new InvalidDataException(Path.GetFileName(file));
        int n = info.NodeCount;
        if (n > 200_000_000) throw new InvalidDataException(Path.GetFileName(file));
        var cmp = new ScanComparison(info, root, n);

        using var r = new BinaryReader(new BufferedStream(new GZipStream(fs, CompressionMode.Decompress, leaveOpen: true), 1 << 16), Encoding.UTF8);
        var bytes = new byte[256];
        var chars = new char[256];
        int next = 1;
        for (int i = 0; i < n; i++)
        {
            int len = r.Read7BitEncodedInt();
            if (len < 0) throw new InvalidDataException();
            if (len > bytes.Length)
            {
                bytes = new byte[len];
                chars = new char[len];
            }
            r.BaseStream.ReadExactly(bytes, 0, len);
            int cc = Encoding.UTF8.GetChars(bytes, 0, len, chars, 0);
            cmp._hash[i] = ScanSnapshot.NameHash(chars.AsSpan(0, cc));
            cmp._index[i] = i;
            cmp._size[i] = r.Read7BitEncodedInt64();
            cmp._files[i] = r.Read7BitEncodedInt64();
            r.Read7BitEncodedInt64(); // DirCount: chưa dùng khi so sánh
            r.ReadByte();             // cờ
            int kids = r.Read7BitEncodedInt();
            if (kids < 0 || next + kids > n) throw new InvalidDataException();
            cmp._first[i] = next;
            cmp._count[i] = kids;
            next += kids;
        }
        if (next != n) throw new InvalidDataException();

        for (int i = 0; i < n; i++)
            if (cmp._count[i] > 1) Array.Sort(cmp._hash, cmp._index, cmp._first[i], cmp._count[i]);
        return cmp;
    }

    /// <summary>Vị trí của thư mục trong lần quét cũ, -1 nếu khi đó chưa có (thư mục mới).</summary>
    public int IndexOf(DirNode node)
    {
        if (ReferenceEquals(node, Root)) return 0;
        if (_found.TryGetValue(node, out int idx)) return idx;
        idx = node.Parent is { } parent ? IndexOf(parent) : -1;
        if (idx >= 0) idx = FindChild(idx, ScanSnapshot.NameHash(node.Name));
        _found[node] = idx;
        return idx;
    }

    private int FindChild(int parent, ulong hash)
    {
        int lo = _first[parent], hi = lo + _count[parent] - 1;
        while (lo <= hi)
        {
            int mid = lo + ((hi - lo) >> 1);
            ulong h = _hash[mid];
            if (h == hash) return _index[mid];
            if (h < hash) lo = mid + 1; else hi = mid - 1;
        }
        return -1;
    }

    public long SizeAt(int index) => _size[index];
    public long FilesAt(int index) => _files[index];

    /// <summary>Dung lượng thay đổi so với lần quét cũ; thư mục mới thì là toàn bộ dung lượng của nó.</summary>
    public long SizeChange(DirNode node)
    {
        int i = IndexOf(node);
        return Interlocked.Read(ref node.Size) - (i >= 0 ? _size[i] : 0);
    }
}
