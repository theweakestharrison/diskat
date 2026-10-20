using System.ComponentModel;
using System.Globalization;
using System.Windows.Data;
using System.Windows.Markup;

namespace Diskat.Core;

/// <summary>
/// Bản địa hóa đơn giản: tiếng Anh mặc định, có thể chuyển sang tiếng Việt.
/// XAML dùng {core:T Key}; mã C# dùng Loc.T("Key") / Loc.F("Key", args).
/// </summary>
public sealed class Loc : INotifyPropertyChanged
{
    public static Loc I { get; } = new();
    public static string Lang { get; private set; } = "en";
    public static event Action? LanguageChanged;
    public event PropertyChangedEventHandler? PropertyChanged;

    private static readonly string SettingsFile =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Diskat", "lang.txt");

    public string this[string key] => T(key);

    public static string T(string key) =>
        S.TryGetValue(key, out var v) ? (Lang == "vi" ? v.vi : v.en) : key;

    public static string F(string key, params object[] args) =>
        string.Format(CultureInfo.InvariantCulture, T(key), args);

    public static void Load()
    {
        try
        {
            if (File.Exists(SettingsFile) && File.ReadAllText(SettingsFile).Trim() == "vi") Lang = "vi";
        }
        catch { }
    }

    public static void SetLanguage(string lang)
    {
        if (lang == Lang) return;
        Lang = lang == "vi" ? "vi" : "en";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(SettingsFile)!);
            File.WriteAllText(SettingsFile, Lang);
        }
        catch { }
        I.PropertyChanged?.Invoke(I, new PropertyChangedEventArgs("Item[]"));
        LanguageChanged?.Invoke();
    }

    private static readonly Dictionary<string, (string en, string vi)> S = new()
    {
        // Cửa sổ chính
        ["WindowTitle"] = ("Diskat", "Diskat"),
        ["AppSubtitle"] = ("Find what's eating your disk space", "Tìm thư mục chiếm nhiều dung lượng"),
        ["PathTip"] = ("Type a path and press Enter to scan", "Nhập đường dẫn rồi nhấn Enter để quét"),
        ["Browse"] = ("Choose folder…", "Chọn thư mục…"),
        ["BrowseTip"] = ("Pick a folder to analyze", "Chọn một thư mục để quét"),
        ["BrowseTitle"] = ("Choose a folder to analyze", "Chọn thư mục cần phân tích"),
        ["Scan"] = ("Scan", "Quét"),
        ["Stop"] = ("Stop", "Dừng"),
        ["Admin"] = ("Run as Admin", "Quyền Admin"),
        ["AdminTip"] = ("Restart with Administrator rights to scan protected system folders",
                        "Khởi động lại với quyền Administrator để quét cả các thư mục hệ thống bị chặn"),
        ["LangTip"] = ("Language / Ngôn ngữ", "Ngôn ngữ / Language"),

        // Cây thư mục
        ["TreeTitle"] = ("Folder tree", "Cây thư mục"),
        ["NoSelection"] = ("Nothing selected", "Chưa chọn mục nào"),
        ["Collapse"] = ("Collapse", "Thu gọn"),
        ["CollapseTip"] = ("Collapse all folders", "Thu gọn tất cả thư mục"),
        ["Open"] = ("Open", "Mở"),
        ["OpenTip"] = ("Open in Explorer", "Mở trong Explorer"),
        ["Delete"] = ("Delete", "Xóa"),
        ["DeleteTip"] = ("Move the selected item to the Recycle Bin (Del)", "Xóa mục đang chọn vào Thùng rác (Del)"),
        ["DeletePerm"] = ("Delete permanently", "Xóa vĩnh viễn"),
        ["DeletePermTip"] = ("Delete permanently, cannot be undone (Shift+Del)", "Xóa vĩnh viễn, không thể khôi phục (Shift+Del)"),
        ["ColName"] = ("Name", "Tên"),
        ["ColSize"] = ("Size", "Kích thước"),
        ["ColPercent"] = ("% of parent", "% thư mục cha"),
        ["ColFiles"] = ("Files", "Số file"),
        ["ColFolders"] = ("Folders", "Thư mục"),
        ["ColModified"] = ("Modified", "Sửa đổi"),
        ["ColFileName"] = ("File name", "Tên file"),
        ["ColFolder"] = ("Folder", "Thư mục"),
        ["EmptyTitle"] = ("Pick a drive above or choose a folder to get started", "Chọn một ổ đĩa ở trên hoặc một thư mục để bắt đầu"),
        ["EmptySub"] = ("Scans run in parallel and the heaviest folders float to the top",
                        "Ứng dụng sẽ quét song song và sắp xếp thư mục nặng nhất lên đầu"),
        ["SelFiles"] = (" · {0} files", " · {0} file"),

        // Menu
        ["MenuExplorer"] = ("Open in Explorer", "Mở trong Explorer"),
        ["MenuShowInExplorer"] = ("Show in Explorer", "Hiện trong Explorer"),
        ["MenuOpen"] = ("Open", "Mở"),
        ["MenuCopy"] = ("Copy path", "Sao chép đường dẫn"),
        ["MenuMap"] = ("Show on space map", "Xem bản đồ thư mục này"),
        ["MenuRescan"] = ("Rescan this folder", "Quét lại thư mục này"),
        ["MenuRecycle"] = ("Delete (to Recycle Bin)", "Xóa (vào Thùng rác)"),
        ["MenuDeletePerm"] = ("Delete permanently", "Xóa vĩnh viễn"),

        // Bên phải
        ["TabMap"] = ("Space map", "Bản đồ dung lượng"),
        ["TabTopFiles"] = ("Largest files", "File lớn nhất"),
        ["MapUpTip"] = ("Up to parent folder", "Lên thư mục cha"),
        ["MapHint"] = ("Hover a tile for details · Click to select · Double-click to drill in",
                       "Di chuột lên ô để xem chi tiết · Nhấp để chọn · Nhấp đúp để đi vào thư mục"),
        ["MapFiles"] = ("[{0} files]", "[{0} file]"),
        ["MapOthers"] = ("[{0} more items]", "[{0} mục khác]"),

        // Trạng thái
        ["Ready"] = ("Ready", "Sẵn sàng"),
        ["Deleting"] = ("Deleting…", "Đang xóa…"),
        ["DeletingPerm"] = ("Deleting permanently…", "Đang xóa vĩnh viễn…"),
        ["Recycling"] = ("Moving to Recycle Bin…", "Đang chuyển vào Thùng rác…"),
        ["Scanning"] = ("Scanning: {0}", "Đang quét: {0}"),
        ["Stats"] = ("{0}  ·  {1} files  ·  {2} folders  ·  {3:0.0}s", "{0}  ·  {1} file  ·  {2} thư mục  ·  {3:0.0}s"),
        ["StatsBlocked"] = ("  ·  {0} folders blocked", "  ·  {0} thư mục bị chặn"),
        ["ScanStopped"] = ("Stopped after {0:0.0}s. Results are incomplete.", "Đã dừng sau {0:0.0}s, kết quả chưa đầy đủ."),
        ["ScanDone"] = ("Done in {0:0.0}s ({1} files/sec).", "Hoàn tất trong {0:0.0}s ({1} file/giây)."),
        ["ScanDoneBlocked"] = (" Some folders were blocked. Click “Run as Admin” for a full scan.",
                               " Một số thư mục bị chặn, bấm “Quyền Admin” để quét đầy đủ."),
        ["Freed"] = ("Freed {0}: {1}", "Đã giải phóng {0}: {1}"),
        ["FreedShort"] = ("Freed {0}", "Đã giải phóng {0}"),
        ["Rescanning"] = ("Rescanning: {0}", "Đang quét lại: {0}"),
        ["Rescanned"] = ("Rescanned: {0} ({1})", "Đã quét lại: {0} ({1})"),

        // Ổ đĩa
        ["DriveUsb"] = ("USB Drive", "USB"),
        ["DriveNetwork"] = ("Network Drive", "Ổ mạng"),
        ["DriveCd"] = ("CD/DVD", "CD/DVD"),
        ["DriveLocal"] = ("Local Disk", "Ổ đĩa cục bộ"),
        ["DriveFree"] = ("{0} free of {1}", "Trống {0} / {1}"),
        ["DriveTip"] = ("{0} ({1})\nUsed: {2}\nFree: {3}\nClick to scan the whole drive",
                        "{0} ({1})\nĐã dùng: {2}\nCòn trống: {3}\nNhấp để quét toàn bộ ổ"),

        // Dòng
        ["MoreFiles"] = ("… and {0} smaller files", "… và {0} file nhỏ khác"),
        ["NoteDenied"] = ("Access denied", "Không có quyền truy cập"),
        ["NoteLink"] = ("Link (junction/symlink), not counted", "Liên kết (junction/symlink), không tính"),
        ["DateFormat"] = ("yyyy-MM-dd HH:mm", "dd/MM/yyyy HH:mm"),

        // Thông báo
        ["MsgNotFound"] = ("Folder not found:\n{0}", "Không tìm thấy thư mục:\n{0}"),
        ["MsgWaitScan"] = ("Please wait for the scan to finish (or click Stop) before deleting.",
                           "Vui lòng đợi quét xong (hoặc bấm Dừng) trước khi xóa."),
        ["MsgRootDelete"] = ("The folder being analyzed can't be deleted here.\nScan its parent folder if you want to delete it.",
                             "Không thể xóa thư mục gốc đang được phân tích.\nHãy quét thư mục cha của nó nếu muốn xóa."),
        ["MsgNotAllowed"] = ("Not allowed", "Không được phép xóa"),
        ["MsgDeleteFailed"] = ("Could not delete everything:\n{0}\n\n{1}", "Không thể xóa hết:\n{0}\n\n{1}"),
        ["MsgDeleteErrorTitle"] = ("Delete error", "Lỗi xóa"),
        ["MsgError"] = ("An error occurred:\n\n{0}", "Đã xảy ra lỗi:\n\n{0}"),
        ["ProtInvalid"] = ("Invalid path.", "Đường dẫn không hợp lệ."),
        ["ProtDrive"] = ("A whole drive can't be deleted.", "Không thể xóa cả ổ đĩa."),
        ["ProtSystem"] = ("This is a critical system folder (or contains one).", "Đây là thư mục hệ thống quan trọng (hoặc chứa thư mục hệ thống)."),
        ["ProtWindows"] = ("Deleting inside the Windows folder is blocked because it could break the operating system.",
                           "Không cho phép xóa bên trong thư mục Windows vì có thể làm hỏng hệ điều hành."),
        ["ProtOddName"] = ("This name ends with a dot or a space. Windows tools would act on a different item with the same name, so Diskat won't delete it.",
                           "Tên này kết thúc bằng dấu chấm hoặc khoảng trắng. Công cụ của Windows sẽ thao tác nhầm sang mục khác cùng tên, nên Diskat không xóa."),
        ["ProtProfile"] = ("This is the root folder of a user account.", "Đây là thư mục gốc của một tài khoản người dùng."),
        ["NoteBadName"] = ("Name ends with a dot or space, skipped", "Tên kết thúc bằng dấu chấm/khoảng trắng, bỏ qua"),
        ["ConfirmIncomplete"] = ("⚠  This folder was not fully scanned (scan stopped or access denied). It may be larger than shown.",
                                 "⚠  Thư mục này chưa được quét đầy đủ (đã dừng quét hoặc bị chặn quyền). Dung lượng thật có thể lớn hơn số hiển thị."),
        ["MsgBusy"] = ("Please wait for the current operation to finish.", "Vui lòng đợi thao tác hiện tại hoàn tất."),
        ["RecycleError"] = ("Could not delete (error code 0x{0:X}).", "Không thể xóa (mã lỗi 0x{0:X})."),

        // Hộp xác nhận
        ["ConfirmWindowTitle"] = ("Confirm delete", "Xác nhận xóa"),
        ["WhatFolder"] = ("this folder", "thư mục này"),
        ["WhatFile"] = ("this file", "file này"),
        ["WhatFiles"] = ("{0} files", "{0} file"),
        ["SelectedFiles"] = ("{0} selected files", "{0} file đã chọn"),
        ["ConfirmPermTitle"] = ("Permanently delete {0}?", "Xóa vĩnh viễn {0}?"),
        ["ConfirmRecycleTitle"] = ("Move {0} to the Recycle Bin?", "Chuyển {0} vào Thùng rác?"),
        ["ConfirmPermSub"] = ("This action can't be undone.", "Thao tác này không thể hoàn tác."),
        ["ConfirmRecycleSub"] = ("You can restore it from the Recycle Bin if needed.", "Bạn có thể khôi phục lại từ Thùng rác nếu cần."),
        ["ConfirmSize"] = ("Size: ", "Dung lượng: "),
        ["ConfirmWarn"] = ("⚠  Data will be erased from the disk and can NOT be restored from the Recycle Bin.",
                           "⚠  Dữ liệu sẽ bị xóa hẳn khỏi ổ đĩa và KHÔNG thể khôi phục từ Thùng rác."),
        ["DetailDir"] = ("{0} files  ·  {1} subfolders", "{0} file  ·  {1} thư mục con"),
        ["Cancel"] = ("Cancel", "Hủy"),
        ["BtnRecycle"] = ("Move to Recycle Bin", "Chuyển vào Thùng rác"),
        ["BtnDeletePerm"] = ("Delete permanently", "Xóa vĩnh viễn"),
    };
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
