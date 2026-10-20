using System.IO.Enumeration;
using System.IO.Hashing;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Diskat.Core;

/// <summary>Một file trong nhóm trùng lặp. Các tên khác của cùng một file (hard link) được gộp vào đây.</summary>
public sealed class DupFile
{
    public required string Path { get; init; }
    public DateTime LastWriteUtc { get; init; }
    /// <summary>Tổng số tên (hard link) của file trên ổ đĩa, kể cả các tên nằm ngoài thư mục quét.</summary>
    public int LinkCount { get; init; } = 1;
    /// <summary>Các tên khác của cùng file tìm thấy trong thư mục quét.</summary>
    public IReadOnlyList<string> OtherNames { get; init; } = [];
    /// <summary>Xóa một tên của file có nhiều hard link không giải phóng được chỗ nào.</summary>
    public bool IsHardLinked => LinkCount > 1;
}

public sealed class DupGroup
{
    public DupGroup(long size, List<DupFile> files)
    {
        Size = size;
        Files = files;
        Wasted = size * Math.Min(files.Count - 1, files.Count(f => !f.IsHardLinked));
    }

    public long Size { get; }
    public List<DupFile> Files { get; }
    /// <summary>Dung lượng giải phóng được khi chỉ giữ một bản (chỉ tính những bản xóa được).</summary>
    public long Wasted { get; }
}

public sealed record DupResult(List<DupGroup> Groups, long Files, long CloudSkipped, long Unreadable);

/// <summary>
/// Tìm file trùng nội dung trong cả cây thư mục: nhóm theo dung lượng, rồi so 64 KB đầu,
/// cuối cùng mới băm toàn bộ (XxHash128) những file vẫn còn giống nhau.
/// Không đọc file "chỉ có trên mạng" (OneDrive...) để không tải gì về; nhiều tên của cùng một file
/// (hard link) được tính là một file.
/// </summary>
public static class DuplicateFinder
{
    public const int HeadSize = 64 * 1024;
    private const int BufferSize = 1 << 20;

    public sealed class Progress
    {
        /// <summary>0: liệt kê file, 1: so phần đầu, 2: so toàn bộ nội dung.</summary>
        public int Stage;
        /// <summary>Số file đủ lớn đã liệt kê.</summary>
        public long Found;
        /// <summary>Bước 1: số file; bước 2: số byte.</summary>
        public long Done;
        public long Total;
    }

    private sealed class Entry
    {
        public required string Path;
        public long Size;
        public DateTime LastWriteUtc;
        public bool Ok;
        public ulong Volume;
        public UInt128 Id;
        public int Links;
        public UInt128 Head;
        public UInt128 Rest;
        public List<string>? Others;
    }

    // Dữ liệu chỉ có trên mạng (OneDrive "Files On-Demand", lưu trữ HSM): đọc vào sẽ tải cả file về
    private const FileAttributes RecallOnOpen = (FileAttributes)0x40000;
    private const FileAttributes RecallOnDataAccess = (FileAttributes)0x400000;
    private const FileAttributes CloudOnly = FileAttributes.Offline | RecallOnOpen | RecallOnDataAccess;

    public static DupResult Find(string root, long minSize, bool skipSystem, Progress progress, CancellationToken ct)
    {
        minSize = Math.Max(1, minSize); // file rỗng giống nhau nhưng không tốn chỗ
        var skipDirs = skipSystem ? SystemFolders() : null;
        string? usersDir = skipSystem ? UsersDir() : null;
        long cloud = 0;

        // ---- Bước 0: liệt kê, nhóm theo dung lượng ----
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = 0, // file "chỉ có trên mạng" cũng là reparse point: liệt kê để đếm rồi bỏ qua
            BufferSize = 64 * 1024,
        };
        var en = new FileSystemEnumerable<Entry>(root,
            (ref FileSystemEntry e) => new Entry { Path = e.ToFullPath(), Size = e.Length, LastWriteUtc = e.LastWriteTimeUtc.UtcDateTime }, options)
        {
            // Giống FileFinder: không đi vào junction / symlink và tên kết thúc bằng "." hoặc " "
            ShouldRecursePredicate = (ref FileSystemEntry e) =>
                (e.Attributes & FileAttributes.ReparsePoint) == 0 && e.FileName.Length > 0 && e.FileName[^1] is not ('.' or ' ')
                && (skipDirs == null || !IsSkippedDir(ref e, skipDirs, usersDir)),
            ShouldIncludePredicate = (ref FileSystemEntry e) =>
            {
                ct.ThrowIfCancellationRequested();
                if (e.IsDirectory || e.Length < minSize) return false;
                // "foo." bị Win32 đọc thành "foo": có thể so nhầm sang một file khác
                if (e.FileName[^1] is '.' or ' ') return false;
                if ((e.Attributes & CloudOnly) != 0) { cloud++; return false; }
                if (skipDirs != null && (e.Attributes & FileAttributes.System) != 0) return false;
                return true;
            },
        };

        var bySize = new Dictionary<long, List<Entry>>();
        long found = 0;
        foreach (var f in en)
        {
            if (!bySize.TryGetValue(f.Size, out var list)) bySize[f.Size] = list = new List<Entry>(2);
            list.Add(f);
            Volatile.Write(ref progress.Found, ++found);
        }

        // ---- Bước 1: mở các file cùng dung lượng, lấy mã file và băm 64 KB đầu ----
        var heads = bySize.Values.Where(l => l.Count > 1).SelectMany(l => l).ToList();
        bySize.Clear();
        // Đọc theo thứ tự đường dẫn: các file cùng thư mục thường nằm gần nhau trên ổ cứng HDD
        heads.Sort((a, b) => string.Compare(a.Path, b.Path, StringComparison.OrdinalIgnoreCase));
        var (headThreads, fullThreads) = Parallelism(root);
        long unreadable = 0;

        progress.Done = 0;
        progress.Total = heads.Count;
        Volatile.Write(ref progress.Stage, 1);
        Parallel.ForEach(heads, new ParallelOptions { MaxDegreeOfParallelism = headThreads, CancellationToken = ct },
            () => new byte[HeadSize],
            (e, _, buf) =>
            {
                if (!ct.IsCancellationRequested)
                {
                    ReadHead(e, buf);
                    if (!e.Ok) Interlocked.Increment(ref unreadable);
                }
                Interlocked.Increment(ref progress.Done);
                return buf;
            },
            _ => { });
        ct.ThrowIfCancellationRequested();

        // Gộp các tên của cùng một file (hard link), rồi nhóm theo (dung lượng, 64 KB đầu)
        var seen = new Dictionary<(ulong, UInt128), Entry>();
        var byHead = new Dictionary<(long, UInt128), List<Entry>>();
        foreach (var e in heads)
        {
            if (!e.Ok) continue;
            if (seen.TryGetValue((e.Volume, e.Id), out var first))
            {
                (first.Others ??= []).Add(e.Path);
                continue;
            }
            seen[(e.Volume, e.Id)] = e;
            if (!byHead.TryGetValue((e.Size, e.Head), out var list)) byHead[(e.Size, e.Head)] = list = new List<Entry>(2);
            list.Add(e);
        }
        var sameHead = byHead.Values.Where(l => l.Count > 1).ToList();

        // ---- Bước 2: băm phần còn lại của những file vẫn giống nhau ----
        var full = sameHead.SelectMany(l => l).Where(e => e.Size > HeadSize).ToList();
        full.Sort((a, b) => string.Compare(a.Path, b.Path, StringComparison.OrdinalIgnoreCase));
        progress.Done = 0;
        progress.Total = full.Sum(e => e.Size - HeadSize);
        Volatile.Write(ref progress.Stage, 2);
        Parallel.ForEach(full, new ParallelOptions { MaxDegreeOfParallelism = fullThreads, CancellationToken = ct },
            () => new byte[BufferSize],
            (e, _, buf) =>
            {
                HashRest(e, buf, progress, ct);
                if (!e.Ok && !ct.IsCancellationRequested) Interlocked.Increment(ref unreadable);
                return buf;
            },
            _ => { });
        ct.ThrowIfCancellationRequested();

        // ---- Kết quả: nhóm theo toàn bộ nội dung, lãng phí nhiều nhất trước ----
        var groups = new List<DupGroup>();
        foreach (var list in sameHead)
        {
            foreach (var g in list.Where(e => e.Ok).GroupBy(e => e.Rest))
            {
                var items = g.ToList();
                if (items.Count < 2) continue;
                var files = items
                    .OrderByDescending(e => e.LastWriteUtc)
                    .ThenBy(e => e.Path, StringComparer.OrdinalIgnoreCase)
                    .Select(e => new DupFile
                    {
                        Path = e.Path,
                        LastWriteUtc = e.LastWriteUtc,
                        LinkCount = Math.Max(1, e.Links),
                        OtherNames = e.Others ?? [],
                    })
                    .ToList();
                // Bản nào cũng có hard link khác: xóa bản nào cũng không lấy lại được chỗ
                if (files.All(f => f.IsHardLinked)) continue;
                groups.Add(new DupGroup(items[0].Size, files));
            }
        }
        groups.Sort((a, b) => a.Wasted != b.Wasted ? b.Wasted.CompareTo(a.Wasted)
            : string.Compare(a.Files[0].Path, b.Files[0].Path, StringComparison.OrdinalIgnoreCase));
        return new DupResult(groups, found, cloud, unreadable);
    }

    private static void ReadHead(Entry e, byte[] buf)
    {
        try
        {
            using var h = Open(e.Path);
            if (h == null || !GetIdentity(h, e)) return;
            int want = (int)Math.Min(HeadSize, e.Size);
            int n = 0;
            while (n < want)
            {
                int r = RandomAccess.Read(h, buf.AsSpan(n, want - n), n);
                if (r <= 0) return; // file ngắn đi sau khi liệt kê
                n += r;
            }
            e.Head = XxHash128.HashToUInt128(buf.AsSpan(0, n));
            e.Ok = true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    private static void HashRest(Entry e, byte[] buf, Progress p, CancellationToken ct)
    {
        e.Ok = false;
        try
        {
            using var h = Open(e.Path);
            if (h == null) return;
            var hash = new XxHash128();
            long offset = HeadSize, end = e.Size;
            while (offset < end)
            {
                if (ct.IsCancellationRequested) return;
                int n = RandomAccess.Read(h, buf.AsSpan(0, (int)Math.Min(buf.Length, end - offset)), offset);
                if (n <= 0) return; // file ngắn đi trong lúc đọc
                hash.Append(buf.AsSpan(0, n));
                offset += n;
                Interlocked.Add(ref p.Done, n);
            }
            // File đã dài ra so với lúc liệt kê: nội dung đang thay đổi, không coi là bản sao
            if (RandomAccess.GetLength(h) != e.Size) return;
            e.Rest = hash.GetCurrentHashAsUInt128();
            e.Ok = true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    // ---------------- Thư mục hệ thống ----------------

    private static string? UsersDir()
    {
        try { return Path.GetDirectoryName(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile).TrimEnd('\\')); }
        catch { return null; }
    }

    /// <summary>Windows, Program Files, ProgramData: ứng dụng thường có file giống hệt nhau ở đây, xóa đi sẽ hỏng ứng dụng.</summary>
    private static HashSet<string> SystemFolders()
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        void Add(string? p)
        {
            try { if (!string.IsNullOrEmpty(p)) set.Add(Path.GetFullPath(p).TrimEnd('\\')); } catch { }
        }
        Add(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86));
        Add(Environment.GetEnvironmentVariable("ProgramW6432"));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData));
        return set;
    }

    private static bool IsSkippedDir(ref FileSystemEntry e, HashSet<string> skip, string? usersDir)
    {
        var name = e.FileName;
        if (name.Equals("$Recycle.Bin", StringComparison.OrdinalIgnoreCase) ||
            name.Equals("System Volume Information", StringComparison.OrdinalIgnoreCase))
            return true;
        // AppData của mọi tài khoản (C:\Users\<tên>\AppData): dữ liệu và bản cài của ứng dụng
        if (usersDir != null && name.Equals("AppData", StringComparison.OrdinalIgnoreCase) &&
            Path.GetDirectoryName(e.Directory).Equals(usersDir, StringComparison.OrdinalIgnoreCase))
            return true;
        return skip.Contains(e.ToFullPath());
    }

    // ---------------- Đọc file ----------------

    /// <summary>
    /// Mở để đọc mà không chặn chương trình khác. FILE_FLAG_OPEN_NO_RECALL: nếu dữ liệu chỉ có trên mạng
    /// thì đọc thất bại chứ không tải về. Tiền tố \\?\ để Win32 không sửa tên file.
    /// </summary>
    private static SafeFileHandle? Open(string path)
    {
        string p = path.StartsWith(@"\\?\", StringComparison.Ordinal) ? path
            : path.StartsWith(@"\\", StringComparison.Ordinal) ? @"\\?\UNC\" + path[2..]
            : @"\\?\" + path;
        var h = CreateFile(p, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, IntPtr.Zero,
            OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN | FILE_FLAG_OPEN_NO_RECALL, IntPtr.Zero);
        if (!h.IsInvalid) return h;
        h.Dispose();
        return null;
    }

    private static bool GetIdentity(SafeFileHandle h, Entry e)
    {
        if (!GetFileInformationByHandle(h, out var info)) return false;
        e.Links = (int)info.NumberOfLinks;
        e.Volume = info.VolumeSerialNumber;
        e.Id = ((ulong)info.FileIndexHigh << 32) | info.FileIndexLow;
        // ReFS dùng mã file 128 bit, 64 bit ở trên không chắc là duy nhất
        if (GetFileInformationByHandleEx(h, FileIdInfo, out FILE_ID_INFO id, (uint)Marshal.SizeOf<FILE_ID_INFO>()))
        {
            e.Volume = id.VolumeSerialNumber;
            e.Id = new UInt128(id.IdHigh, id.IdLow);
        }
        return true;
    }

    /// <summary>Số luồng đọc: SSD đọc song song nhanh hơn; ổ cứng HDD đọc lần lượt để đầu đọc không phải nhảy qua lại.</summary>
    private static (int Head, int Full) Parallelism(string root)
    {
        if (IncursSeekPenalty(root) == true) return (1, 1);
        int cpu = Environment.ProcessorCount;
        return (Math.Clamp(cpu, 2, 8), Math.Clamp(cpu / 2, 1, 4));
    }

    private static bool? IncursSeekPenalty(string root)
    {
        try
        {
            var drive = Path.GetPathRoot(Path.GetFullPath(root));
            if (drive is not { Length: >= 2 } || drive[1] != ':') return null; // đường dẫn mạng
            using var h = CreateFile(@"\\.\" + drive[..2], 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
            if (h.IsInvalid) return null;
            var q = new STORAGE_PROPERTY_QUERY { PropertyId = StorageDeviceSeekPenaltyProperty };
            if (!DeviceIoControl(h, IOCTL_STORAGE_QUERY_PROPERTY, ref q, Marshal.SizeOf<STORAGE_PROPERTY_QUERY>(),
                    out DEVICE_SEEK_PENALTY_DESCRIPTOR d, Marshal.SizeOf<DEVICE_SEEK_PENALTY_DESCRIPTOR>(), out _, IntPtr.Zero))
                return null;
            return d.IncursSeekPenalty != 0;
        }
        catch { return null; }
    }

    // ---------------- Win32 ----------------

    private const uint GENERIC_READ = 0x80000000;
    private const uint FILE_SHARE_READ = 0x1, FILE_SHARE_WRITE = 0x2, FILE_SHARE_DELETE = 0x4;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_SEQUENTIAL_SCAN = 0x08000000;
    private const uint FILE_FLAG_OPEN_NO_RECALL = 0x00100000;
    private const int FileIdInfo = 18;
    private const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
    private const int StorageDeviceSeekPenaltyProperty = 7;

    [StructLayout(LayoutKind.Sequential)]
    private struct BY_HANDLE_FILE_INFORMATION
    {
        public uint FileAttributes;
        public uint CreationLow, CreationHigh, AccessLow, AccessHigh, WriteLow, WriteHigh;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh, FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh, FileIndexLow;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FILE_ID_INFO
    {
        public ulong VolumeSerialNumber;
        public ulong IdLow, IdHigh;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct STORAGE_PROPERTY_QUERY
    {
        public int PropertyId;
        public int QueryType;
        public int AdditionalParameters;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DEVICE_SEEK_PENALTY_DESCRIPTOR
    {
        public uint Version;
        public uint Size;
        public byte IncursSeekPenalty;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle h, out BY_HANDLE_FILE_INFORMATION info);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandleEx(SafeFileHandle h, int infoClass, out FILE_ID_INFO info, uint size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(SafeFileHandle h, uint code, ref STORAGE_PROPERTY_QUERY input, int inputSize,
        out DEVICE_SEEK_PENALTY_DESCRIPTOR output, int outputSize, out int returned, IntPtr overlapped);
}
