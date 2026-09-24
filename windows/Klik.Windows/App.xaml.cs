using System.Windows;
using Klik.Windows.Services;

namespace Klik.Windows;

public partial class App : System.Windows.Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        RecorderService.CleanupAbandonedSessions();
        base.OnStartup(e);
        DispatcherUnhandledException += (_, args) =>
        {
            System.Windows.MessageBox.Show(args.Exception.Message, "Klik", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };
    }
}
