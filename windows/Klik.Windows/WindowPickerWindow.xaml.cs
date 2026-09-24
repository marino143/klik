using Klik.Windows.Services;
using System.Windows;
using System.Windows.Input;

namespace Klik.Windows;

public partial class WindowPickerWindow : Window
{
    public WindowInfo? SelectedWindow => WindowList.SelectedItem as WindowInfo;

    public WindowPickerWindow()
    {
        InitializeComponent();
        WindowList.ItemsSource = WindowCatalog.GetRecordableWindows();
        if (WindowList.Items.Count > 0) WindowList.SelectedIndex = 0;
    }

    private void OnChoose(object sender, RoutedEventArgs e)
    {
        if (SelectedWindow is null) return;
        DialogResult = true;
    }

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
    private void OnDoubleClick(object sender, MouseButtonEventArgs e) => OnChoose(sender, e);

    private void OnKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape) DialogResult = false;
        if (e.Key == Key.Enter) OnChoose(sender, e);
    }
}
