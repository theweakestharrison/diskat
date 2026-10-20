using System.Diagnostics;
using System.Globalization;
using System.IO.Enumeration;
using System.Runtime.InteropServices;

namespace Diskat.Core;

public readonly record struct FileItem(string Name, long Size, DateTime LastWriteUtc);

public static class FileOps
{
    private static readonly string[] Units = ["B", "KB", "MB", "GB", "TB", "PB"];

    public static string FormatSize(long bytes)
    {
        if (bytes < 1024) return bytes.ToString(CultureInfo.InvariantCulture) + " B";
        double v = bytes;
        int u = 0;
        while (v >= 1024 && u < Units.Length - 1) { v /= 1024; u++; }
        string fmt = v >= 100 ? "0" : v >= 10 ? "0.0" : "0.00";
        return v.ToString(fmt, CultureInfo.InvariantCulture) + " " + Units[u];
    }

    public static string FormatCount(long n) => n.ToString("#,0", CultureInfo.InvariantCulture);

    private static readonly EnumerationOptions FileOptions = new()
    {
        RecurseSubdirectories = false,
        IgnoreInaccessible = true,
        AttributesToSkip = 0,
        BufferSize = 64 * 1024,
    };

    /// <summary>Liệt kê các file nằm trực tiếp trong thư mục (không đệ quy).</summary>
    public static List<FileItem> ListFiles(string dir)
    {
        var result = new List<FileItem>();
        try
        {
            var en = new FileSystemEnumerable<FileItem>(dir,
                (ref FileSystemEntry e) => new FileItem(e.FileName.ToString(), e.Length, e.LastWriteTimeUtc.UtcDateTime),
                FileOptions)
            { ShouldIncludePredicate = (ref FileSystemEntry e) => !e.IsDirectory };
            result.AddRange(en);
        }
        catch { }
        return result;
    }

    // ---------------- An toàn ----------------

    private static string Norm(string p) => Path.GetFullPath(p).TrimEnd('\\') + "\\";

    /// <summary>Trả về lý do nếu đường dẫn không được phép xóa, ngược lại null.</summary>
    public static string? GetProtectionReason(string path)
    {
        // Tên kết thúc bằng "." hoặc " " bị Win32 tự cắt bỏ: "foo." sẽ trỏ nhầm sang "foo"
        if (HasTrailingDotOrSpace(path)) return Loc.T("ProtOddName");

        if (CheckProtected(path) is { } reason) return reason;

        // Kiểm tra cả đường dẫn thật (qua ổ subst, junction ở thư mục cha, v.v.)
        var real = TryGetFinalPath(path);
        if (real != null && !string.Equals(real.TrimEnd('\\'), path.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
            return CheckProtected(real);
        return null;
    }

    private static string? CheckProtected(string path)
    {
        string full;
        try { full = Norm(path); } catch { return Loc.T("ProtInvalid"); }

        if (Path.GetPathRoot(full)?.TrimEnd('\\') + "\\" == full)
            return Loc.T("ProtDrive");

        var critical = new List<string>();
        void Add(string? s)
        {
            try { if (!string.IsNullOrEmpty(s)) critical.Add(Norm(s)); } catch { }
        }
        string F(Environment.SpecialFolder f) => Environment.GetFolderPath(f);
        string? usersDir = null;
        try { usersDir = Path.GetDirectoryName(F(Environment.SpecialFolder.UserProfile)); } catch { }

        Add(F(Environment.SpecialFolder.Windows));
        Add(F(Environment.SpecialFolder.ProgramFiles));
        Add(F(Environment.SpecialFolder.ProgramFilesX86));
        Add(F(Environment.SpecialFolder.CommonApplicationData));
        Add(Path.Join(F(Environment.SpecialFolder.CommonApplicationData), "Microsoft"));
        Add(F(Environment.SpecialFolder.UserProfile));
        Add(F(Environment.SpecialFolder.ApplicationData));
        Add(F(Environment.SpecialFolder.LocalApplicationData));
        Add(usersDir);

        foreach (var c in critical)
        {
            // Chính thư mục hệ thống, hoặc thư mục chứa nó
            if (c.StartsWith(full, StringComparison.OrdinalIgnoreCase))
                return Loc.T("ProtSystem");
        }

        // Thư mục gốc của bất kỳ tài khoản người dùng nào (C:\Users\<tên>)
        if (usersDir != null)
        {
            var parent = Path.GetDirectoryName(full.TrimEnd('\\'));
            if (parent != null && string.Equals(Norm(parent), Norm(usersDir), StringComparison.OrdinalIgnoreCase))
                return Loc.T("ProtProfile");
        }

        var win = F(Environment.SpecialFolder.Windows);
        if (!string.IsNullOrEmpty(win) && full.StartsWith(Norm(win), StringComparison.OrdinalIgnoreCase))
            return Loc.T("ProtWindows");

        return null;
    }

    /// <summary>True nếu một phần của đường dẫn kết thúc bằng dấu chấm hoặc khoảng trắng.</summary>
    public static bool HasTrailingDotOrSpace(string path)
    {
        var root = Path.GetPathRoot(path) ?? "";
        foreach (var seg in path[root.Length..].Split('\\', '/', StringSplitOptions.RemoveEmptyEntries))
            if (seg != "." && seg != ".." && (seg.EndsWith('.') || seg.EndsWith(' ')))
                return true;
        return false;
    }

    /// <summary>Đường dẫn thật trên đĩa sau khi giải quyết subst / junction / symlink; null nếu không lấy được.</summary>
    private static string? TryGetFinalPath(string path)
    {
        using var h = CreateFile(path, 0, FILE_SHARE_ALL, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero);
        if (h.IsInvalid) return null;
        var sb = new System.Text.StringBuilder(1024);
        uint n = GetFinalPathNameByHandle(h, sb, (uint)sb.Capacity, 0);
        if (n == 0 || n >= sb.Capacity) return null;
        var s = sb.ToString();
        if (s.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) return @"\\" + s[8..];
        if (s.StartsWith(@"\\?\", StringComparison.Ordinal)) return s[4..];
        return s;
    }

    // ---------------- Xóa ----------------

    public static void DeletePermanently(string path, bool isDirectory)
    {
        if (!isDirectory)
        {
            var fi = new FileInfo(path);
            if (fi.Exists && fi.IsReadOnly) fi.IsReadOnly = false;
            fi.Delete();
            return;
        }
        try
        {
            Directory.Delete(path, true);
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException)
        {
            // Bỏ thuộc tính chỉ-đọc rồi thử lại. AttributesToSkip = ReparsePoint: không đi vào
            // junction/symlink, nếu không sẽ sửa thuộc tính của file nằm NGOÀI thư mục cần xóa.
            var di = new DirectoryInfo(path);
            if (di.LinkTarget == null)
            {
                foreach (var info in di.EnumerateFileSystemInfos("*", new EnumerationOptions
                         { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint }))
                {
                    try
                    {
                        if ((info.Attributes & FileAttributes.ReadOnly) != 0)
                            info.Attributes &= ~FileAttributes.ReadOnly;
                    }
                    catch { }
                }
            }
            try { di.Attributes &= ~FileAttributes.ReadOnly; } catch { }
            Directory.Delete(path, true);
        }
    }

    /// <summary>Đưa vào Thùng rác qua Shell (SHFileOperation). Trả về false nếu người dùng hủy.</summary>
    public static bool SendToRecycleBin(string path, IntPtr owner)
    {
        bool ok = false;
        Exception? error = null;
        var t = new Thread(() =>
        {
            try
            {
                var op = new SHFILEOPSTRUCT
                {
                    hwnd = owner,
                    wFunc = FO_DELETE,
                    pFrom = path + "\0\0",
                    fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_WANTNUKEWARNING | FOF_SILENT,
                };
                int rc = SHFileOperation(ref op);
                if (op.fAnyOperationsAborted) ok = false;
                else if (rc != 0) error = new IOException(Loc.F("RecycleError", rc));
                else ok = true;
            }
            catch (Exception ex) { error = ex; }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();
        if (error != null) throw error;
        return ok && !Path.Exists(path);
    }

    public static void ShowInExplorer(string path)
    {
        try
        {
            if (Directory.Exists(path) && !File.Exists(path))
                Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
            else
                Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
        }
        catch { }
    }

    public static void SelectInExplorer(string path)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true }); }
        catch { }
    }

    public static void OpenWithShell(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { }
    }

    // ---------------- Win32 ----------------

    private const uint FO_DELETE = 0x0003;
    private const ushort FOF_SILENT = 0x0004;
    private const ushort FOF_NOCONFIRMATION = 0x0010;
    private const ushort FOF_ALLOWUNDO = 0x0040;
    private const ushort FOF_WANTNUKEWARNING = 0x4000;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string? pTo;
        public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string? lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT lpFileOp);

    private const uint FILE_SHARE_ALL = 0x7; // read | write | delete
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000; // cần để mở thư mục

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string name, uint access, uint share,
        IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle h,
        System.Text.StringBuilder path, uint len, uint flags);
}
