using System.Windows;
using System.Windows.Threading;
using Diskat.Core;

namespace Diskat;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        Loc.Load();
        DispatcherUnhandledException += OnUnhandled;
        base.OnStartup(e);
    }

    private static void OnUnhandled(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        MessageBox.Show(Loc.F("MsgError", e.Exception.Message), "Diskat",
            MessageBoxButton.OK, MessageBoxImage.Error);
        e.Handled = true;
    }
}
