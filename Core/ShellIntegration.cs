using Microsoft.Win32;

namespace Diskat.Core;

/// <summary>
/// Mục "Quét bằng Diskat" trong menu chuột phải của Explorer (thư mục, ổ đĩa, nền thư mục).
/// Ghi vào HKCU nên không cần quyền Admin và chỉ ảnh hưởng tài khoản hiện tại. Người dùng tự bật / tắt.
/// Trên Windows 11, mục này nằm trong "Show more options".
/// </summary>
public static class ShellIntegration
{
    private const string Verb = "Diskat";

    // (khóa, tham số đường dẫn): %1 = mục được bấm chuột phải, %V = thư mục đang mở (bấm vào nền)
    private static readonly (string Key, string Arg)[] Targets =
    [
        (@"Software\Classes\Directory\shell\" + Verb, "%1"),
        (@"Software\Classes\Drive\shell\" + Verb, "%1"),
        (@"Software\Classes\Directory\Background\shell\" + Verb, "%V"),
    ];

    public static bool IsInstalled
    {
        get
        {
            try { using var k = Registry.CurrentUser.OpenSubKey(Targets[0].Key); return k != null; }
            catch { return false; }
        }
    }

    private static string ExePath => Environment.ProcessPath ?? throw new InvalidOperationException("no process path");

    public static void Install(string label)
    {
        string exe = ExePath;
        foreach (var (key, arg) in Targets)
        {
            using var k = Registry.CurrentUser.CreateSubKey(key);
            k.SetValue("", label);
            k.SetValue("Icon", $"\"{exe}\",0");
            using var cmd = k.CreateSubKey("command");
            cmd.SetValue("", $"\"{exe}\" \"{arg}\"");
        }
    }

    public static void Uninstall()
    {
        foreach (var (key, _) in Targets)
        {
            try { Registry.CurrentUser.DeleteSubKeyTree(key, throwOnMissingSubKey: false); } catch { }
        }
    }

    /// <summary>
    /// Bản Diskat dạng một file exe có thể bị chuyển chỗ hoặc đổi ngôn ngữ: cập nhật lại lệnh và nhãn
    /// nếu mục đã được bật. Không làm gì nếu người dùng chưa bật.
    /// </summary>
    public static void RefreshIfInstalled(string label)
    {
        try
        {
            if (!IsInstalled) return;
            using var k = Registry.CurrentUser.OpenSubKey(Targets[0].Key);
            using var cmd = Registry.CurrentUser.OpenSubKey(Targets[0].Key + @"\command");
            // Lệnh dạng "C:\...\Diskat.exe" "%1": lấy đường dẫn exe trong cặp ngoặc kép đầu tiên
            string? registered = (cmd?.GetValue("") as string)?.Split('"', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
            bool moved = registered == null || !File.Exists(registered);
            bool same = string.Equals(registered, ExePath, StringComparison.OrdinalIgnoreCase);
            // Không "giành" mục của một bản Diskat khác vẫn còn trên máy (vd. bản đang dùng so với bản thử)
            if (moved || (same && k?.GetValue("") as string != label)) Install(label);
        }
        catch { }
    }
}
