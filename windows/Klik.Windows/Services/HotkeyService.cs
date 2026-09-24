using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Klik.Windows.Services;

public sealed class HotkeyService : IDisposable
{
    private const int WmHotkey = 0x0312;
    private const uint ModWin = 0x0008;
    private const uint ModShift = 0x0004;

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(nint hWnd, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(nint hWnd, int id);

    private readonly nint _handle;
    private readonly HwndSource _source;
    private readonly Dictionary<int, Action> _actions = new();

    public HotkeyService(System.Windows.Window window)
    {
        _handle = new WindowInteropHelper(window).Handle;
        _source = HwndSource.FromHwnd(_handle) ?? throw new InvalidOperationException("Klik could not register shortcuts.");
        _source.AddHook(WndProc);
    }

    public bool Register(int id, char key, Action action)
    {
        if (!RegisterHotKey(_handle, id, ModWin | ModShift, key)) return false;
        _actions[id] = action;
        return true;
    }

    private nint WndProc(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == WmHotkey && _actions.TryGetValue(wParam.ToInt32(), out var action))
        {
            action();
            handled = true;
        }
        return 0;
    }

    public void Dispose()
    {
        foreach (var id in _actions.Keys) UnregisterHotKey(_handle, id);
        _source.RemoveHook(WndProc);
        _actions.Clear();
    }
}
