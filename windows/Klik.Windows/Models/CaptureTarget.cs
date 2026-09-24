namespace Klik.Windows.Models;

public enum CaptureKind
{
    Display,
    Region,
    Window
}

public sealed record CaptureTarget(
    CaptureKind Kind,
    string DisplayDeviceName,
    CaptureRect? Region = null,
    nint WindowHandle = 0,
    string? Label = null);

public readonly record struct CaptureRect(double X, double Y, double Width, double Height);

public enum AudioMode
{
    Speakers,
    Headphones
}
