using System.Runtime.InteropServices;
using System.Text;

namespace Klik.Windows.Services;

public sealed record WindowInfo(nint Handle, string Title, string ProcessName);

public static class WindowCatalog
{
    private delegate bool EnumWindowsProc(nint hWnd, nint lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, nint lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(nint hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(nint hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(nint hWnd);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hWnd, out uint processId);

    public static IReadOnlyList<WindowInfo> GetRecordableWindows()
    {
        var windows = new List<WindowInfo>();
        EnumWindows((handle, _) =>
        {
            if (!IsWindowVisible(handle)) return true;
            var length = GetWindowTextLength(handle);
            if (length == 0) return true;

            var title = new StringBuilder(length + 1);
            _ = GetWindowText(handle, title, title.Capacity);
            GetWindowThreadProcessId(handle, out var processId);
            string processName;
            try
            {
                processName = System.Diagnostics.Process.GetProcessById((int)processId).ProcessName;
            }
            catch
            {
                processName = "Application";
            }

            if (!string.Equals(processName, "Klik", StringComparison.OrdinalIgnoreCase))
                windows.Add(new WindowInfo(handle, title.ToString(), processName));
            return true;
        }, 0);

        return windows
            .OrderBy(window => window.ProcessName)
            .ThenBy(window => window.Title)
            .ToArray();
    }
}
