using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Diskat.Core;
using Diskat.UI;

namespace Diskat;

/// <summary>Menu "Thêm" (⋯): báo cáo PDF, kiểm tra cập nhật, giới thiệu.</summary>
public partial class MainWindow
{
    private bool _checkingUpdates;

    private void MoreBtn_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = MoreBtn, Placement = PlacementMode.Bottom };

        menu.Items.Add(CompareMenuItem());
        menu.Items.Add(new Separator());

        bool canExport = CanExport;
        var pdf = new MenuItem { Header = Loc.T("MenuExportPdf"), IsEnabled = canExport };
        pdf.Click += (_, _) => _ = ExportPdfAsync();
        menu.Items.Add(pdf);

        var csvFolders = new MenuItem { Header = Loc.T("MenuExportFolders"), IsEnabled = canExport };
        csvFolders.Click += (_, _) => _ = ExportFoldersCsvAsync();
        menu.Items.Add(csvFolders);

        var topList = TopFiles.ItemsSource as IEnumerable<TopFileVM>;
        var csvFiles = new MenuItem { Header = Loc.T("MenuExportFiles"), IsEnabled = canExport && topList?.Any() == true };
        csvFiles.Click += (_, _) => _ = ExportFilesCsvAsync(topList!.ToList(), Loc.T("CsvFilesTitle"));
        menu.Items.Add(csvFiles);
        menu.Items.Add(new Separator());

        var check = new MenuItem { Header = Loc.T("MenuCheckUpdates"), IsEnabled = !_checkingUpdates };
        check.Click += (_, _) => _ = CheckForUpdatesAsync(userInitiated: true);
        menu.Items.Add(check);

        if (!Updater.IsPackaged)
        {
            var auto = new MenuItem
            {
                Header = Loc.T("MenuAutoUpdate"),
                IsCheckable = true,
                IsChecked = Settings.Current.CheckForUpdatesOnStartup,
            };
            auto.Click += (_, _) =>
            {
                Settings.Current.CheckForUpdatesOnStartup = auto.IsChecked;
                Settings.Current.Save();
            };
            menu.Items.Add(auto);

            // Store (MSIX) ghi registry vào vùng ảo của gói, Explorer không thấy: chỉ có ở bản exe
            var shell = new MenuItem { Header = Loc.T("MenuShellEntry"), IsCheckable = true, IsChecked = ShellIntegration.IsInstalled };
            shell.Click += (_, _) =>
            {
                try
                {
                    if (shell.IsChecked) ShellIntegration.Install(Loc.T("ShellVerb"));
                    else ShellIntegration.Uninstall();
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, Loc.F("ShellFailed", ex.Message), "Diskat", MessageBoxButton.OK, MessageBoxImage.Warning);
                }
            };
            menu.Items.Add(new Separator());
            menu.Items.Add(shell);
        }
        else menu.Items.Add(new Separator());
        menu.Items.Add(ThemeMenu());

        menu.Items.Add(new Separator());
        var about = new MenuItem { Header = Loc.T("MenuAbout") };
        about.Click += (_, _) => MessageBox.Show(this, Loc.F("AboutText", Updater.CurrentVersion), "Diskat",
            MessageBoxButton.OK, MessageBoxImage.Information);
        menu.Items.Add(about);

        menu.IsOpen = true;
    }

    /// <summary>Menu con Giao diện: theo Windows, sáng hoặc tối. Đổi ngay và lưu vào settings.json.</summary>
    private static MenuItem ThemeMenu()
    {
        var root = new MenuItem { Header = Loc.T("MenuTheme") };
        foreach (var (theme, key) in new[] { (AppTheme.System, "ThemeSystem"), (AppTheme.Light, "ThemeLight"), (AppTheme.Dark, "ThemeDark") })
        {
            var item = new MenuItem { Header = Loc.T(key), IsCheckable = true, IsChecked = Settings.Current.Theme == theme };
            item.Click += (_, _) => Theme.Set(theme);
            root.Items.Add(item);
        }
        return root;
    }

    /// <summary>
    /// Kiểm tra bản mới. userInitiated = false: lần kiểm tra tự động lúc mở app (chỉ khi người dùng đã bật),
    /// khi đó không báo gì nếu đang ở bản mới nhất hoặc không có mạng.
    /// </summary>
    private async Task CheckForUpdatesAsync(bool userInitiated)
    {
        if (_checkingUpdates) return;
        if (Updater.IsPackaged)
        {
            if (userInitiated)
                MessageBox.Show(this, Loc.T("UpdStore"), "Diskat", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        _checkingUpdates = true;
        var previous = _status;
        if (userInitiated) SetStatus(() => Loc.T("UpdChecking"));
        try
        {
            var info = await Updater.CheckAsync();
            if (userInitiated) SetStatus(previous);
            if (info != null) UpdateDialog.Show(this, info);
            else if (userInitiated)
                MessageBox.Show(this, Loc.F("UpdUpToDate", Updater.CurrentVersion), "Diskat", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            if (userInitiated)
            {
                SetStatus(previous);
                MessageBox.Show(this, Loc.F("UpdCheckFailed", ex.Message), "Diskat", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
        finally { _checkingUpdates = false; }
    }

    /// <summary>Gọi khi cửa sổ đã mở: kiểm tra tự động tối đa một lần mỗi ngày, chỉ khi người dùng bật.</summary>
    private void MaybeCheckForUpdatesOnStartup()
    {
        var s = Settings.Current;
        if (!s.CheckForUpdatesOnStartup || Updater.IsPackaged) return;
        if (s.LastUpdateCheckUtc is { } last && DateTime.UtcNow - last < TimeSpan.FromHours(20)) return;
        _ = CheckForUpdatesAsync(userInitiated: false);
    }
}
