using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Microsoft.Win32;
using Diskat.Core;

namespace Diskat.UI;

/// <summary>
/// Giao diện sáng / tối. Mặc định theo Windows (chế độ ứng dụng trong Cài đặt > Cá nhân hóa > Màu),
/// người dùng có thể chọn cố định trong menu ⋯. Đổi ngay lúc chạy: thay từ điển màu Themes/Light.xaml / Dark.xaml
/// (mọi màu trong XAML là DynamicResource) rồi báo cho phần tự vẽ (bản đồ, biểu tượng trong cây) vẽ lại.
/// </summary>
public static class Theme
{
    public static bool IsDark { get; private set; }

    /// <summary>Gọi trên luồng giao diện sau khi đã đổi màu.</summary>
    public static event Action? Changed;

    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private static bool _ready;

    /// <summary>Gọi một lần lúc khởi động, trước khi mở cửa sổ chính.</summary>
    public static void Init()
    {
        Apply();
        // Đổi chế độ sáng / tối trong Windows gửi WM_SETTINGCHANGE "ImmersiveColorSet", tức nhóm General
        SystemEvents.UserPreferenceChanged += (_, e) =>
        {
            if (e.Category == UserPreferenceCategory.General)
                Application.Current?.Dispatcher.BeginInvoke(Apply);
        };
        // Cửa sổ mở sau (hộp thoại...) cũng nhận thanh tiêu đề đúng màu
        EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent,
            new RoutedEventHandler((s, _) => SetTitleBar((Window)s)));
    }

    public static void Set(AppTheme theme)
    {
        Settings.Current.Theme = theme;
        Settings.Current.Save();
        Apply();
    }

    private static void Apply()
    {
        bool dark = Settings.Current.Theme switch
        {
            AppTheme.Dark => true,
            AppTheme.Light => false,
            _ => SystemUsesDark(),
        };
        if (_ready && dark == IsDark) return;

        // App.xaml nạp sẵn Light.xaml: chỉ thay khi khác
        if (dark != IsDark)
        {
            var merged = Application.Current.Resources.MergedDictionaries;
            var colors = new ResourceDictionary
            {
                Source = new Uri($"pack://application:,,,/Diskat;component/Themes/{(dark ? "Dark" : "Light")}.xaml"),
            };
            int i = merged.ToList().FindIndex(IsColorDictionary);
            if (i >= 0) merged[i] = colors;
            else merged.Insert(0, colors);
        }
        IsDark = dark;
        _ready = true;

        Palette.Load();
        foreach (Window w in Application.Current.Windows) SetTitleBar(w);
        Changed?.Invoke();
    }

    private static bool IsColorDictionary(ResourceDictionary d) =>
        d.Source?.OriginalString is { } s && (s.EndsWith("Light.xaml", StringComparison.OrdinalIgnoreCase) ||
                                              s.EndsWith("Dark.xaml", StringComparison.OrdinalIgnoreCase));

    /// <summary>AppsUseLightTheme = 0 nghĩa là Windows đang để ứng dụng ở chế độ tối. Không có khóa: sáng.</summary>
    private static bool SystemUsesDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
            return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
        }
        catch { return false; }
    }

    // ---------------- Thanh tiêu đề ----------------

    private const int DwmUseImmersiveDarkMode = 20;    // Windows 10 20H1 trở lên, Windows 11
    private const int DwmUseImmersiveDarkModeOld = 19; // Windows 10 1809 đến 1909
    private const int WmNcActivate = 0x0086;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);

    /// <summary>Thanh tiêu đề do Windows vẽ: sáng hay tối theo giao diện hiện tại.</summary>
    public static void SetTitleBar(Window w)
    {
        var hwnd = new WindowInteropHelper(w).Handle;
        if (hwnd == IntPtr.Zero) return;
        int on = IsDark ? 1 : 0;
        if (DwmSetWindowAttribute(hwnd, DwmUseImmersiveDarkMode, ref on, sizeof(int)) != 0)
            DwmSetWindowAttribute(hwnd, DwmUseImmersiveDarkModeOld, ref on, sizeof(int));

        // Windows 10 chỉ vẽ lại thanh tiêu đề khi cửa sổ đổi trạng thái kích hoạt: nhắc nó vẽ ngay
        if (w.IsVisible && w.WindowStyle != WindowStyle.None)
        {
            SendMessage(hwnd, WmNcActivate, w.IsActive ? IntPtr.Zero : 1, IntPtr.Zero);
            SendMessage(hwnd, WmNcActivate, w.IsActive ? 1 : IntPtr.Zero, IntPtr.Zero);
        }
    }
}
