using Klik.Windows.Services;
using Xunit;

namespace Klik.Windows.Tests;

public class RecordingCaptureExclusionTests
{
    [Fact]
    public void AppliesExactExclusionToEachCurrentHandle()
    {
        var calls = new List<(nint, uint)>();
        foreach (nint handle in new nint[] { 10, 20 })
            RecordingCaptureExclusion.Apply(handle, true, () => true,
                (h, value) => calls.Add((h, value)), _ => 0x11);
        Assert.Equal(new[] { ((nint)10, 0x11u), ((nint)20, 0x11u) }, calls);
    }

    [Theory]
    [InlineData(false, 10, true)]
    [InlineData(true, 0, true)]
    [InlineData(true, 10, false)]
    public void UnsupportedStateNeverSetsMonitorFallback(bool supported, int handle, bool composition)
    {
        var called = false;
        Assert.ThrowsAny<Exception>(() => RecordingCaptureExclusion.Apply(
            handle, supported, () => composition, (_, _) => called = true, _ => 0x11));
        Assert.False(called);
    }

    [Fact]
    public void NativeFailureIsNotSilentlyIgnored()
    {
        Assert.Throws<System.ComponentModel.Win32Exception>(() => RecordingCaptureExclusion.Apply(
            10, true, () => true, (_, _) => throw new System.ComponentModel.Win32Exception(5),
            _ => throw new Exception("Must not read after failed write")));
    }

    [Theory]
    [InlineData(0u)]
    [InlineData(1u)]
    public void RejectsMissingOrBlankRectangleAffinity(uint actual)
    {
        Assert.Throws<InvalidOperationException>(() => RecordingCaptureExclusion.Apply(
            10, true, () => true, (_, _) => { }, _ => actual));
    }
}
