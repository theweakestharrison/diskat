namespace Diskat.Core;

/// <summary>
/// Tham số dòng lệnh:
///   Diskat.exe [thư mục] [--pdf file.pdf] [--csv thư-mục.csv] [--files-csv file.csv] [--lang vi]
///              [--shell-menu on|off] [--quit]
/// Thư mục được quét ngay; các file xuất được ghi sau khi quét xong; --quit đóng Diskat khi đã xuất xong.
/// </summary>
public sealed class CommandLine
{
    public string? ScanPath { get; private set; }
    public string? PdfPath { get; private set; }
    public string? FoldersCsvPath { get; private set; }
    public string? FilesCsvPath { get; private set; }
    public string? Lang { get; private set; }
    public bool Quit { get; private set; }
    /// <summary>--shell-menu on|off: bật / tắt mục "Quét bằng Diskat" trong Explorer.</summary>
    public bool? ShellMenu { get; private set; }
    public bool HasExports => PdfPath != null || FoldersCsvPath != null || FilesCsvPath != null;

    public static CommandLine Parse(IReadOnlyList<string> args)
    {
        var cl = new CommandLine();
        for (int i = 0; i < args.Count; i++)
        {
            string a = args[i];
            string? Next() => i + 1 < args.Count ? Full(args[++i]) : null;
            switch (a.ToLowerInvariant())
            {
                case "--pdf": cl.PdfPath = Next(); break;
                case "--csv": cl.FoldersCsvPath = Next(); break;
                case "--files-csv": cl.FilesCsvPath = Next(); break;
                case "--lang": cl.Lang = i + 1 < args.Count ? args[++i].ToLowerInvariant() : null; break;
                case "--quit": cl.Quit = true; break;
                case "--shell-menu":
                    cl.ShellMenu = i + 1 < args.Count ? args[++i].ToLowerInvariant() is "on" or "1" or "true" : null;
                    break;
                default:
                    if (!a.StartsWith("--", StringComparison.Ordinal) && cl.ScanPath == null) cl.ScanPath = CleanPath(a);
                    break;
            }
        }
        return cl;
    }

    /// <summary>
    /// Explorer truyền ổ đĩa dạng "C:\" trong ngoặc kép, và quy tắc tách tham số của Windows biến nó thành C:"
    /// (dấu \ trước " bị hiểu là ký tự thoát). Sửa lại thành C:\.
    /// </summary>
    private static string CleanPath(string a)
    {
        a = a.Trim().TrimEnd('"');
        if (a.Length == 2 && a[1] == ':') a += "\\";
        return a;
    }

    private static string? Full(string a)
    {
        try { return Path.GetFullPath(CleanPath(a)); } catch { return null; }
    }
}
