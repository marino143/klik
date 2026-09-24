using System.Windows;

namespace Klik.Windows;

public partial class App : System.Windows.Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += (_, args) =>
        {
            System.Windows.MessageBox.Show(args.Exception.Message, "Klik", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };
    }
}
