using Klik.Windows.Models;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using Forms = System.Windows.Forms;

namespace Klik.Windows.Services;

public static class ScreenshotService
{
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(nint hWnd, out NativeRect rect);

    [DllImport("user32.dll")]
    private static extern bool PrintWindow(nint hWnd, nint hdcBlt, uint flags);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static string Capture(CaptureTarget target, string outputFolder)
    {
        Directory.CreateDirectory(outputFolder);
        var outputPath = Path.Combine(outputFolder, $"Klik {DateTime.Now:yyyy-MM-dd HH-mm-ss}.png");
        using var bitmap = target.Kind switch
        {
            CaptureKind.Window => CaptureWindow(target.WindowHandle),
            CaptureKind.Region when target.Region is { } region => CaptureRectangle(
                new Rectangle((int)region.X, (int)region.Y, (int)region.Width, (int)region.Height)),
            _ => CaptureDisplay(target.DisplayDeviceName)
        };
        bitmap.Save(outputPath, ImageFormat.Png);
        return outputPath;
    }

    private static Bitmap CaptureDisplay(string deviceName)
    {
        var screen = Forms.Screen.AllScreens.FirstOrDefault(item => item.DeviceName == deviceName)
            ?? Forms.Screen.PrimaryScreen
            ?? throw new InvalidOperationException("No display is available.");
        return CaptureRectangle(screen.Bounds);
    }

    private static Bitmap CaptureRectangle(Rectangle bounds)
    {
        var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size, CopyPixelOperation.SourceCopy);
        return bitmap;
    }

    private static Bitmap CaptureWindow(nint handle)
    {
        if (!GetWindowRect(handle, out var rect))
            throw new InvalidOperationException("The selected window is no longer available.");
        var width = Math.Max(1, rect.Right - rect.Left);
        var height = Math.Max(1, rect.Bottom - rect.Top);
        var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        var hdc = graphics.GetHdc();
        try
        {
            if (!PrintWindow(handle, hdc, 2))
                graphics.CopyFromScreen(rect.Left, rect.Top, 0, 0, new Size(width, height));
        }
        finally
        {
            graphics.ReleaseHdc(hdc);
        }
        return bitmap;
    }
}
