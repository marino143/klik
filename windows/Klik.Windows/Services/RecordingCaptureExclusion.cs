using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Klik.Windows.Services;

internal static class RecordingCaptureExclusion
{
    internal const uint ExcludeFromCapture = 0x00000011;

    internal static void Apply(nint window) => Apply(
        window, OperatingSystem.IsWindowsVersionAtLeast(10, 0, 19041),
        () => DwmIsCompositionEnabled(out var enabled) == 0 && enabled,
        (handle, affinity) =>
        {
            if (!SetWindowDisplayAffinity(handle, affinity))
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Windows could not exclude the recording controls. Recording was not started.");
        },
        handle =>
        {
            if (!GetWindowDisplayAffinity(handle, out var affinity))
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Windows could not verify recording control exclusion. Recording was not started.");
            return affinity;
        });

    // Dependencies make failure handling testable without a desktop or user32.
    internal static void Apply(nint window, bool supported, Func<bool> compositionEnabled,
        Action<nint, uint> set, Func<nint, uint> get)
    {
        if (!supported)
            throw new PlatformNotSupportedException(
                "Excluding recording controls requires Windows 10 version 2004 (build 19041) or newer.");
        if (window == 0)
            throw new InvalidOperationException("The recording controls do not have a window handle yet.");
        if (!compositionEnabled())
            throw new InvalidOperationException("Desktop composition is unavailable. Recording controls cannot be excluded.");
        // Never fall back to WDA_MONITOR: it produces a blank rectangle instead
        // of the underlying pixels. Keep the controls visible and reject capture.
        set(window, ExcludeFromCapture);
        if (get(window) != ExcludeFromCapture)
            throw new InvalidOperationException("Windows did not retain recording control exclusion. Recording was not started.");
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowDisplayAffinity(nint window, uint affinity);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowDisplayAffinity(nint window, out uint affinity);

    [DllImport("dwmapi.dll")]
    private static extern int DwmIsCompositionEnabled([MarshalAs(UnmanagedType.Bool)] out bool enabled);
}
