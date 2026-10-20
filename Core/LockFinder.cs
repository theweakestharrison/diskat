using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Diskat.Core;

public sealed record LockingProcess(int Pid, string ProcessName, string AppName, bool CanClose, bool IsExplorer);

public sealed record LockReport(IReadOnlyList<string> LockedFiles, IReadOnlyList<LockingProcess> Processes, bool MoreFilesNotChecked);

/// <summary>
/// Tìm chương trình đang giữ file (dùng Windows Restart Manager), đóng chúng theo yêu cầu,
/// hoặc hẹn xóa khi Windows khởi động lại.
/// </summary>
public static class LockFinder
{
    private const int MaxFilesToTest = 20000;
    private const int MaxLockedFiles = 200;

    /// <summary>Lỗi "đang được dùng" (sharing / lock violation).</summary>
    public static bool IsInUseError(Exception ex)
    {
        int code = ex.HResult & 0xFFFF;
        return code is 32 or 33; // ERROR_SHARING_VIOLATION, ERROR_LOCK_VIOLATION
    }

    public static LockReport Inspect(string path, bool isDirectory)
    {
        var locked = new List<string>();
        var modules = new List<string>(); // exe/dll đang chạy không luôn lộ ra qua phép thử mở độc quyền
        var dirs = new List<string>();    // hỏi trực tiếp handle: thư mục (vd. "thư mục hiện tại" của cmd) và file đơn
        bool more = false;
        dirs.Add(path);
        if (!isDirectory)
        {
            if (IsLocked(path)) locked.Add(path);
            modules.Add(path); // vẫn hỏi Restart Manager: exe đang chạy có thể không lộ ra qua phép thử
        }
        else
        {
            int tested = 0;
            var options = new EnumerationOptions
            {
                RecurseSubdirectories = true, IgnoreInaccessible = true,
                AttributesToSkip = FileAttributes.ReparsePoint, // không đi ra ngoài thư mục qua junction
            };
            try
            {
                foreach (var entry in new DirectoryInfo(path).EnumerateFileSystemInfos("*", options))
                {
                    if (++tested > MaxFilesToTest || locked.Count >= MaxLockedFiles) { more = true; break; }
                    if ((entry.Attributes & FileAttributes.Directory) != 0)
                    {
                        if (dirs.Count < MaxDirsToQuery) dirs.Add(entry.FullName);
                        continue;
                    }
                    if (IsLocked(entry.FullName)) locked.Add(entry.FullName);
                    else if (modules.Count < MaxModules && IsModule(entry.Name)) modules.Add(entry.FullName);
                }
            }
            catch { }
        }

        var processes = new List<LockingProcess>();
        var candidates = locked.Concat(modules).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (candidates.Count > 0) processes.AddRange(GetLockers(candidates));

        // Restart Manager chỉ làm việc với file. Thư mục: hỏi thẳng Windows tiến trình nào đang mở nó.
        foreach (var pid in dirs.SelectMany(ProcessIdsUsing).Distinct())
        {
            if (pid == Environment.ProcessId || processes.Any(p => p.Pid == pid)) continue;
            if (Describe(pid) is { } lp) processes.Add(lp);
        }
        // Thư mục chỉ bị Explorer "nhìn" (cửa sổ đang mở) thì không chặn việc xóa: bỏ qua để khỏi gây nhiễu
        if (locked.Count == 0 && processes.All(p => p.IsExplorer)) processes.Clear();

        return new LockReport(locked, processes, more);
    }

    private const int MaxDirsToQuery = 2000;
    private const int MaxModules = 500;

    private static bool IsModule(string name) =>
        name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase);

    /// <summary>Thông tin một tiến trình không đến từ Restart Manager (tự xếp loại an toàn).</summary>
    private static LockingProcess? Describe(int pid)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            string name = p.ProcessName;
            bool explorer = name.Equals("explorer", StringComparison.OrdinalIgnoreCase);
            // Session 0 là dịch vụ, cộng thêm các tiến trình lõi của Windows: không bao giờ đề nghị đóng
            bool system = p.SessionId == 0 || CoreProcesses.Contains(name);
            string title = "";
            try { title = p.MainWindowTitle; } catch { }
            string app = name;
            try { app = p.MainModule?.FileVersionInfo.FileDescription is { Length: > 0 } d ? d : name; } catch { }
            if (app == name && title.Length > 0) app = title;
            return new LockingProcess(pid, name, app, !system && !explorer, explorer);
        }
        catch { return null; }
    }

    private static readonly HashSet<string> CoreProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "System", "Idle", "Registry", "smss", "csrss", "wininit", "winlogon", "services", "lsass", "lsaiso",
        "svchost", "fontdrvhost", "dwm", "sihost", "ctfmon", "taskhostw", "RuntimeBroker", "SearchIndexer",
        "MsMpEng", "NisSrv", "SecurityHealthService", "spoolsv", "audiodg", "conhost", "dllhost",
    };

    /// <summary>Các PID đang có handle tới file/thư mục (FileProcessIdsUsingFileInformation).</summary>
    private static int[] ProcessIdsUsing(string path)
    {
        using var h = CreateFile(path, FILE_READ_ATTRIBUTES, FILE_SHARE_ALL, IntPtr.Zero, OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero);
        if (h.IsInvalid) return [];
        int size = 1024;
        for (int attempt = 0; attempt < 6; attempt++)
        {
            IntPtr buf = Marshal.AllocHGlobal(size);
            try
            {
                int status = NtQueryInformationFile(h, out _, buf, size, FileProcessIdsUsingFileInformation);
                if (status == STATUS_INFO_LENGTH_MISMATCH) { size *= 4; continue; }
                if (status != 0) return [];
                int count = Marshal.ReadInt32(buf);
                int offset = IntPtr.Size; // ULONG đếm, căn lề theo ULONG_PTR
                var ids = new int[Math.Min(count, (size - offset) / IntPtr.Size)];
                for (int i = 0; i < ids.Length; i++)
                    ids[i] = (int)Marshal.ReadIntPtr(buf, offset + i * IntPtr.Size);
                return ids;
            }
            finally { Marshal.FreeHGlobal(buf); }
        }
        return [];
    }

    /// <summary>Thử mở độc quyền: thất bại vì "đang dùng" nghĩa là chương trình khác đang mở file.</summary>
    private static bool IsLocked(string file)
    {
        try
        {
            using var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.None);
            return false;
        }
        catch (IOException ex) { return IsInUseError(ex); }
        catch { return false; }
    }

    public static List<LockingProcess> GetLockers(IReadOnlyList<string> files)
    {
        var result = new List<LockingProcess>();
        var key = new StringBuilder(CCH_RM_SESSION_KEY + 1);
        if (RmStartSession(out uint session, 0, key) != 0) return result;
        try
        {
            if (RmRegisterResources(session, (uint)files.Count, files.ToArray(), 0, null, 0, null) != 0) return result;

            uint needed = 0, count = 0, reasons = 0;
            int rc = RmGetList(session, out needed, ref count, null, ref reasons);
            if (rc == ERROR_MORE_DATA && needed > 0)
            {
                var infos = new RM_PROCESS_INFO[needed];
                count = needed;
                rc = RmGetList(session, out needed, ref count, infos, ref reasons);
                if (rc != 0) return result;

                int self = Environment.ProcessId;
                foreach (var info in infos.Take((int)count))
                {
                    int pid = info.Process.dwProcessId;
                    if (pid == self || result.Any(r => r.Pid == pid)) continue;
                    string name = "";
                    try { name = Process.GetProcessById(pid).ProcessName; } catch { }
                    bool explorer = info.ApplicationType == RM_APP_TYPE.RmExplorer ||
                                    name.Equals("explorer", StringComparison.OrdinalIgnoreCase);
                    // Không đóng: tiến trình hệ thống quan trọng, dịch vụ, và chính shell Explorer
                    bool canClose = info.ApplicationType is not (RM_APP_TYPE.RmCritical or RM_APP_TYPE.RmService)
                                    && !explorer && !CoreProcesses.Contains(name) && info.TSSessionId != 0;
                    result.Add(new LockingProcess(pid, name, string.IsNullOrWhiteSpace(info.strAppName) ? name : info.strAppName, canClose, explorer));
                }
            }
        }
        finally { RmEndSession(session); }
        return result;
    }

    /// <summary>Gửi lệnh đóng cửa sổ chính (như bấm X). Trả về true nếu tiến trình đã thoát trong thời gian chờ.</summary>
    public static bool TryCloseGracefully(int pid, TimeSpan wait)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            if (p.HasExited) return true;
            if (p.MainWindowHandle != IntPtr.Zero) p.CloseMainWindow();
            return p.WaitForExit(wait);
        }
        catch (ArgumentException) { return true; } // đã thoát
        catch { return false; }
    }

    public static bool ForceClose(int pid)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            p.Kill();
            return p.WaitForExit(TimeSpan.FromSeconds(5));
        }
        catch (ArgumentException) { return true; }
        catch { return false; }
    }

    /// <summary>
    /// Hẹn xóa khi Windows khởi động lại (cần quyền Admin). Thư mục: file trước, rồi thư mục con từ sâu ra ngoài.
    /// Trả về false nếu Windows từ chối (thường là thiếu quyền Admin).
    /// </summary>
    public static bool ScheduleDeleteOnReboot(string path, bool isDirectory)
    {
        if (!isDirectory) return MoveFileEx(path, null, MOVEFILE_DELAY_UNTIL_REBOOT);
        return ScheduleTree(path) && MoveFileEx(path, null, MOVEFILE_DELAY_UNTIL_REBOOT);
    }

    /// <summary>
    /// Hẹn xóa nội dung thư mục theo thứ tự con trước, cha sau (Windows xử lý đúng thứ tự này lúc khởi động).
    /// Junction/symlink chỉ hẹn xóa chính liên kết, không bao giờ đi vào nơi nó trỏ tới.
    /// </summary>
    private static bool ScheduleTree(string dir)
    {
        var options = new EnumerationOptions { IgnoreInaccessible = true, AttributesToSkip = 0 };
        foreach (var entry in new DirectoryInfo(dir).EnumerateFileSystemInfos("*", options))
        {
            bool isDir = (entry.Attributes & FileAttributes.Directory) != 0;
            bool isLink = (entry.Attributes & FileAttributes.ReparsePoint) != 0;
            if (isDir && !isLink && !ScheduleTree(entry.FullName)) return false;
            if (!MoveFileEx(entry.FullName, null, MOVEFILE_DELAY_UNTIL_REBOOT)) return false;
        }
        return true;
    }

    // ---------------- Win32 ----------------

    private const int CCH_RM_SESSION_KEY = 32;
    private const int CCH_RM_MAX_APP_NAME = 255;
    private const int CCH_RM_MAX_SVC_NAME = 63;
    private const int ERROR_MORE_DATA = 234;
    private const uint MOVEFILE_DELAY_UNTIL_REBOOT = 0x4;

    private enum RM_APP_TYPE { RmUnknownApp = 0, RmMainWindow = 1, RmOtherWindow = 2, RmService = 3, RmExplorer = 4, RmConsole = 5, RmCritical = 1000 }

    [StructLayout(LayoutKind.Sequential)]
    private struct RM_UNIQUE_PROCESS
    {
        public int dwProcessId;
        public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct RM_PROCESS_INFO
    {
        public RM_UNIQUE_PROCESS Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_APP_NAME + 1)] public string strAppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_SVC_NAME + 1)] public string strServiceShortName;
        public RM_APP_TYPE ApplicationType;
        public uint AppStatus;
        public uint TSSessionId;
        [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    private static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, StringBuilder strSessionKey);

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    private static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames,
        uint nApplications, RM_UNIQUE_PROCESS[]? rgApplications, uint nServices, string[]? rgsServiceNames);

    [DllImport("rstrtmgr.dll")]
    private static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo,
        [In, Out] RM_PROCESS_INFO[]? rgAffectedApps, ref uint lpdwRebootReasons);

    [DllImport("rstrtmgr.dll")]
    private static extern int RmEndSession(uint pSessionHandle);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool MoveFileEx(string lpExistingFileName, string? lpNewFileName, uint dwFlags);

    private const uint FILE_READ_ATTRIBUTES = 0x80;
    private const uint FILE_SHARE_ALL = 0x7;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
    private const int FileProcessIdsUsingFileInformation = 47;
    private const int STATUS_INFO_LENGTH_MISMATCH = unchecked((int)0xC0000004);

    [StructLayout(LayoutKind.Sequential)]
    private struct IO_STATUS_BLOCK
    {
        public IntPtr Status;
        public UIntPtr Information;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string name, uint access, uint share,
        IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("ntdll.dll")]
    private static extern int NtQueryInformationFile(Microsoft.Win32.SafeHandles.SafeFileHandle handle,
        out IO_STATUS_BLOCK ioStatus, IntPtr buffer, int length, int fileInformationClass);
}
