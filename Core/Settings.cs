using System.Text.Json;

namespace Diskat.Core;

/// <summary>Tùy chọn của người dùng, lưu ở %APPDATA%\Diskat\settings.json (ngôn ngữ vẫn nằm trong lang.txt).</summary>
public sealed class Settings
{
    /// <summary>Tự kiểm tra bản mới khi mở app. Mặc định TẮT: Diskat không kết nối mạng nếu người dùng không yêu cầu.</summary>
    public bool CheckForUpdatesOnStartup { get; set; }

    public DateTime? LastUpdateCheckUtc { get; set; }

    private static readonly string FilePath =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Diskat", "settings.json");

    public static Settings Current { get; } = Load();

    private static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
        }
        catch { }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }
}
