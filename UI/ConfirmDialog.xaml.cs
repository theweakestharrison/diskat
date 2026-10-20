using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Diskat.Core;

namespace Diskat.UI;

public partial class ConfirmDialog : Window
{
    private ConfirmDialog()
    {
        InitializeComponent();
        MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };
    }

    /// <summary>Hộp xác nhận xóa. Với xóa vĩnh viễn, nút mặc định (Enter) là "Hủy" để tránh bấm nhầm.</summary>
    public static bool Ask(Window owner, bool permanent, string what, string path, string size, string detail, string? warning = null)
    {
        var d = new ConfirmDialog { Owner = owner, Title = Loc.T("ConfirmWindowTitle") };
        d.TitleText.Text = Loc.F(permanent ? "ConfirmPermTitle" : "ConfirmRecycleTitle", what);
        d.SubtitleText.Text = Loc.T(permanent ? "ConfirmPermSub" : "ConfirmRecycleSub");
        d.PathText.Text = path;
        d.SizeText.Text = size;
        d.DetailText.Text = detail;
        d.OkBtn.Content = Loc.T(permanent ? "BtnDeletePerm" : "BtnRecycle");
        if (warning != null)
        {
            d.InfoText.Text = warning;
            d.InfoBox.Visibility = Visibility.Visible;
        }

        if (permanent)
        {
            d.WarnBox.Visibility = Visibility.Visible;
            d.IconBg.SetResourceReference(Border.BackgroundProperty, "WarnBg");
            d.IconPath.SetResourceReference(System.Windows.Shapes.Shape.StrokeProperty, "DangerText");
            d.CancelBtn.IsDefault = true;
            d.Loaded += (_, _) => d.CancelBtn.Focus();
        }
        else
        {
            d.OkBtn.IsDefault = true;
            d.Loaded += (_, _) => d.OkBtn.Focus();
        }
        return d.ShowDialog() == true;
    }

    private void Ok_Click(object sender, RoutedEventArgs e) => DialogResult = true;
    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
