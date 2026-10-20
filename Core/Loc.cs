using System.ComponentModel;
using System.Globalization;
using System.Reflection;
using System.Windows.Data;
using System.Windows.Markup;

namespace Diskat.Core;

/// <summary>
/// Bản địa hóa: mỗi ngôn ngữ là một file Core/Lang/Strings.&lt;mã&gt;.cs, mặc định tiếng Anh.
/// Chuỗi thiếu trong một bản dịch sẽ lấy từ tiếng Anh.
/// XAML dùng {core:T Key}; mã C# dùng Loc.T("Key") / Loc.F("Key", args).
/// </summary>
public sealed class Loc : INotifyPropertyChanged
{
    public sealed record Language(string Code, string Name);

    public const string DefaultLanguage = "en";

    /// <summary>Thêm ngôn ngữ mới: tạo Strings.&lt;mã&gt;.cs (trường tên viết hoa chữ đầu, ví dụ "Zh") rồi thêm vào danh sách này.</summary>
    private static readonly Language[] AllLanguages =
    [
        new("en", "English"),
        new("vi", "Tiếng Việt"),
        new("zh", "简体中文"),
        new("ja", "日本語"),
        new("ko", "한국어"),
        new("es", "Español"),
        new("pt", "Português"),
        new("de", "Deutsch"),
        new("fr", "Français"),
        new("ru", "Русский"),
        new("id", "Bahasa Indonesia"),
    ];

    private static readonly Dictionary<string, Dictionary<string, string>> Tables = LoadTables();

    /// <summary>Các ngôn ngữ đã có bản dịch trong app.</summary>
    public static IReadOnlyList<Language> Languages { get; } = AllLanguages.Where(l => Tables.ContainsKey(l.Code)).ToArray();

    public static Loc I { get; } = new();
    public static string Lang { get; private set; } = DefaultLanguage;
    public static event Action? LanguageChanged;
    public event PropertyChangedEventHandler? PropertyChanged;

    private static readonly string SettingsFile =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Diskat", "lang.txt");

    public string this[string key] => T(key);

    public static string T(string key)
    {
        if (Tables.TryGetValue(Lang, out var t) && t.TryGetValue(key, out var v)) return v;
        return Strings.En.TryGetValue(key, out var en) ? en : key;
    }

    public static string F(string key, params object[] args) =>
        string.Format(CultureInfo.InvariantCulture, T(key), args);

    public static void Load()
    {
        try
        {
            if (File.Exists(SettingsFile))
            {
                var code = File.ReadAllText(SettingsFile).Trim();
                if (Tables.ContainsKey(code)) Lang = code;
            }
        }
        catch { }
    }

    /// <summary>Dùng ngôn ngữ này cho lần chạy hiện tại mà không lưu lại (tham số --lang).</summary>
    public static void UseForSession(string code)
    {
        if (Tables.ContainsKey(code)) Lang = code;
    }

    public static void SetLanguage(string code)
    {
        if (code == Lang || !Tables.ContainsKey(code)) return;
        Lang = code;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(SettingsFile)!);
            File.WriteAllText(SettingsFile, Lang);
        }
        catch { }
        I.PropertyChanged?.Invoke(I, new PropertyChangedEventArgs("Item[]"));
        LanguageChanged?.Invoke();
    }

    // Strings.En, Strings.Vi, Strings.Zh... : tìm theo tên trường để thêm ngôn ngữ chỉ cần thêm file
    private static Dictionary<string, Dictionary<string, string>> LoadTables()
    {
        var result = new Dictionary<string, Dictionary<string, string>>();
        foreach (var lang in AllLanguages)
        {
            var name = char.ToUpperInvariant(lang.Code[0]) + lang.Code[1..];
            if (typeof(Strings).GetField(name, BindingFlags.Public | BindingFlags.Static)?.GetValue(null) is Dictionary<string, string> table)
                result[lang.Code] = table;
        }
        return result;
    }
}

/// <summary>Markup extension: Text="{core:T Scan}", tự cập nhật khi đổi ngôn ngữ.</summary>
[MarkupExtensionReturnType(typeof(object))]
public sealed class TExtension : MarkupExtension
{
    public TExtension() { }
    public TExtension(string key) { Key = key; }

    [ConstructorArgument("key")]
    public string Key { get; set; } = "";

    public override object ProvideValue(IServiceProvider serviceProvider) =>
        new Binding($"[{Key}]") { Source = Loc.I, Mode = BindingMode.OneWay }.ProvideValue(serviceProvider);
}
