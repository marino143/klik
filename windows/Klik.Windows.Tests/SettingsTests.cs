using Klik.Windows.Models;
using Xunit;

namespace Klik.Windows.Tests;

public sealed class SettingsTests
{
    [Fact]
    public void CaptureTargetKeepsSelectedRegion()
    {
        var region = new CaptureRect(10, 20, 640, 360);
        var target = new CaptureTarget(CaptureKind.Region, @"\\.\DISPLAY1", region);

        Assert.Equal(CaptureKind.Region, target.Kind);
        Assert.Equal(640, target.Region?.Width);
        Assert.Equal(360, target.Region?.Height);
    }

    [Fact]
    public void AudioModesRemainExplicit()
    {
        Assert.NotEqual(AudioMode.Speakers, AudioMode.Headphones);
    }
}
