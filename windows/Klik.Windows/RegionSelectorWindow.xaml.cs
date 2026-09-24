using System.Windows;
using System.Windows.Input;
using Forms = System.Windows.Forms;

namespace Klik.Windows;

public partial class RegionSelectorWindow : Window
{
    private System.Windows.Point _start;
    private bool _dragging;

    public Rect? SelectedRegion { get; private set; }

    public RegionSelectorWindow(Forms.Screen screen)
    {
        InitializeComponent();
        Left = screen.Bounds.Left;
        Top = screen.Bounds.Top;
        Width = screen.Bounds.Width;
        Height = screen.Bounds.Height;
        Loaded += (_, _) => Activate();
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        _start = e.GetPosition(Surface);
        _dragging = true;
        Selection.Visibility = Visibility.Visible;
        CaptureMouse();
    }

    private void OnMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_dragging) return;
        UpdateSelection(e.GetPosition(Surface));
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (!_dragging) return;
        _dragging = false;
        ReleaseMouseCapture();
        var end = e.GetPosition(Surface);
        UpdateSelection(end);
        var rect = Normalize(_start, end);
        if (rect.Width < 8 || rect.Height < 8) return;
        SelectedRegion = rect;
        DialogResult = true;
    }

    private void UpdateSelection(System.Windows.Point current)
    {
        var rect = Normalize(_start, current);
        System.Windows.Controls.Canvas.SetLeft(Selection, rect.Left);
        System.Windows.Controls.Canvas.SetTop(Selection, rect.Top);
        Selection.Width = rect.Width;
        Selection.Height = rect.Height;
        SizeLabel.Text = $"{Math.Round(rect.Width)} × {Math.Round(rect.Height)}";
    }

    private static Rect Normalize(System.Windows.Point first, System.Windows.Point second)
        => new(Math.Min(first.X, second.X), Math.Min(first.Y, second.Y),
            Math.Abs(second.X - first.X), Math.Abs(second.Y - first.Y));

    private void OnKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape) DialogResult = false;
    }
}
