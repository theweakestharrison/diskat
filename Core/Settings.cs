using System.Text.Json;
using System.Text.Json.Serialization;

namespace Diskat.Core;

/// <summary>Giao diện: theo Windows (mặc định), luôn sáng hoặc luôn tối.</summary>
public enum AppTheme { System, Light, Dark }

/// <summary>Tùy chọn của người dùng, lưu ở %APPDATA%\Diskat\settings.json (ngôn ngữ vẫn nằm trong lang.txt).</summary>
public sealed class Settings
{
    /// <summary>Tự kiểm tra bản mới khi mở app. Mặc định TẮT: Diskat không kết nối mạng nếu người dùng không yêu cầu.</summary>
    public bool CheckForUpdatesOnStartup { get; set; }

    public DateTime? LastUpdateCheckUtc { get; set; }

    /// <summary>Lưu cây thư mục sau mỗi lần quét xong (chỉ trên máy này, Core/ScanSnapshot.cs) để so sánh về sau. Mặc định bật.</summary>
    public bool SaveScanHistory { get; set; } = true;

    [JsonConverter(typeof(JsonStringEnumConverter<AppTheme>))]
    public AppTheme Theme { get; set; }

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
