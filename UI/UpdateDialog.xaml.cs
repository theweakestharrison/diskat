using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using Diskat.Core;

namespace Diskat.UI;

/// <summary>Báo có bản mới; nếu người dùng đồng ý thì tải, kiểm tra SHA-256, thay file và khởi động lại.</summary>
public partial class UpdateDialog : Window
{
    private readonly UpdateInfo _info;
    private CancellationTokenSource? _cts;

    private UpdateDialog(UpdateInfo info)
    {
        InitializeComponent();
        _info = info;
        MessageText.Text = Loc.F("UpdMessage", info.Version, Updater.CurrentVersion);
        MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };
        // Đóng hộp thoại bằng cách nào cũng vậy (Alt+F4, Esc): dừng tải, không tự cài sau đó
        Closed += (_, _) => _cts?.Cancel();
    }

    public static void Show(Window owner, UpdateInfo info) =>
        new UpdateDialog(info) { Owner = owner, Title = Loc.T("UpdTitle") }.ShowDialog();

    private void Notes_Click(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo(_info.NotesUrl) { UseShellExecute = true }); } catch { }
    }

    private void Later_Click(object sender, RoutedEventArgs e)
    {
        _cts?.Cancel();
        DialogResult = false;
    }

    private async void Update_Click(object sender, RoutedEventArgs e)
    {
        UpdateBtn.IsEnabled = false;
        ProgressPanel.Visibility = Visibility.Visible;
        _cts = new CancellationTokenSource();
        var progress = new Progress<double>(p =>
        {
            Progress.Value = p;
            ProgressText.Text = Loc.F("UpdDownloading", p * 100);
        });

        string file;
        try
        {
            file = await Updater.DownloadAsync(_info, progress, _cts.Token);
        }
        catch (OperationCanceledException) { return; }
        catch (Exception ex)
        {
            MessageBox.Show(this, Loc.F("UpdFailed", ex.Message), "Diskat", MessageBoxButton.OK, MessageBoxImage.Error);
            UpdateBtn.IsEnabled = true;
            ProgressPanel.Visibility = Visibility.Collapsed;
            return;
        }

        if (!Updater.CanReplaceRunningExe())
        {
            // Ví dụ Diskat.exe nằm trong Program Files: không tự ghi đè được, đưa người dùng tới file mới
            MessageBox.Show(this, Loc.F("UpdNoWrite", Path.GetDirectoryName(Environment.ProcessPath) ?? "", file),
                "Diskat", MessageBoxButton.OK, MessageBoxImage.Information);
            FileOps.SelectInExplorer(file);
            DialogResult = false;
            return;
        }

        ProgressText.Text = Loc.T("UpdInstalling");
        Updater.InstallAfterExit(file);
        Application.Current.Shutdown();
    }
}
