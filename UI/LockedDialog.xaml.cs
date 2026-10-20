using System.Windows;
using System.Windows.Input;
using Diskat.Core;

namespace Diskat.UI;

public enum LockAction { Cancel, Retry, DeleteOnReboot }

/// <summary>Cho biết chương trình nào đang giữ file và cách xử lý: đóng chúng rồi thử lại, hoặc xóa khi khởi động lại.</summary>
public partial class LockedDialog : Window
{
    private sealed record Item(string Title, string Detail, string Note);

    private readonly LockReport _report;
    private LockAction _result = LockAction.Cancel;

    private LockedDialog(string path, LockReport report)
    {
        InitializeComponent();
        _report = report;
        PathText.Text = path;
        MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };

        if (report.Processes.Count == 0)
        {
            SubText.Text = Loc.T("LockSubUnknown");
            NoneText.Visibility = Visibility.Visible;
            CloseBtn.Content = Loc.T("LockRetry");
        }
        else
        {
            SubText.Text = Loc.T("LockSub");
            ProcessList.ItemsSource = report.Processes.Select(p => new Item(
                p.AppName,
                $"{p.ProcessName}.exe · PID {p.Pid}",
                p.IsExplorer ? Loc.T("LockExplorer") : p.CanClose ? "" : Loc.T("LockSystem"))).ToList();
            if (!report.Processes.Any(p => p.CanClose)) CloseBtn.Content = Loc.T("LockRetry");
        }
        if (report.LockedFiles.Count > 1)
            StatusText.Text = Loc.F("LockFiles", report.LockedFiles.Count + (report.MoreFilesNotChecked ? "+" : ""));
    }

    public static LockAction Ask(Window owner, string path, LockReport report)
    {
        var d = new LockedDialog(path, report) { Owner = owner, Title = Loc.T("LockTitle") };
        d.ShowDialog();
        return d._result;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;

    private void Reboot_Click(object sender, RoutedEventArgs e)
    {
        _result = LockAction.DeleteOnReboot;
        DialogResult = true;
    }

    private async void Close_Click(object sender, RoutedEventArgs e)
    {
        var closable = _report.Processes.Where(p => p.CanClose).ToList();
        if (closable.Count > 0)
        {
            CloseBtn.IsEnabled = RebootBtn.IsEnabled = CancelBtn.IsEnabled = false;

            // 1. Nhờ từng chương trình tự đóng (như bấm nút X), để chúng kịp lưu và giải phóng file
            var stubborn = new List<LockingProcess>();
            foreach (var p in closable)
            {
                StatusText.Text = Loc.F("LockClosing", p.AppName);
                bool closed = await Task.Run(() => LockFinder.TryCloseGracefully(p.Pid, TimeSpan.FromSeconds(6)));
                if (!closed) stubborn.Add(p);
            }

            // 2. Chương trình "cứng đầu": chỉ buộc đóng khi người dùng đồng ý
            if (stubborn.Count > 0)
            {
                var names = string.Join("\n", stubborn.Select(p => $"• {p.AppName} ({p.ProcessName}.exe, PID {p.Pid})"));
                if (MessageBox.Show(this, Loc.F("LockForce", names), Loc.T("LockTitle"),
                        MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) == MessageBoxResult.Yes)
                {
                    foreach (var p in stubborn)
                    {
                        StatusText.Text = Loc.F("LockClosing", p.AppName);
                        await Task.Run(() => LockFinder.ForceClose(p.Pid));
                    }
                }
            }
            // Chờ một chút để Windows nhả handle
            await Task.Delay(400);
        }
        _result = LockAction.Retry;
        DialogResult = true;
    }
}
