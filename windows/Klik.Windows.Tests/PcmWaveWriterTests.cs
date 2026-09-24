using Klik.Windows.Services;
using Xunit;

namespace Klik.Windows.Tests;

public sealed class PcmWaveWriterTests
{
    [Fact]
    public void WritesAValidStereoPcmHeader()
    {
        var path = Path.Combine(Path.GetTempPath(), $"klik-wave-{Guid.NewGuid():N}.wav");
        try
        {
            using (var writer = new PcmWaveWriter(path, 48_000, 2, 16))
                writer.Write(new byte[1_920], 0, 1_920);

            var bytes = File.ReadAllBytes(path);
            Assert.Equal("RIFF", System.Text.Encoding.ASCII.GetString(bytes, 0, 4));
            Assert.Equal("WAVE", System.Text.Encoding.ASCII.GetString(bytes, 8, 4));
            Assert.Equal("data", System.Text.Encoding.ASCII.GetString(bytes, 36, 4));
            Assert.Equal(1_920, BitConverter.ToInt32(bytes, 40));
            Assert.Equal(1_964, bytes.Length);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void RejectsPartialStereoFrames()
    {
        var path = Path.Combine(Path.GetTempPath(), $"klik-wave-{Guid.NewGuid():N}.wav");
        try
        {
            using var writer = new PcmWaveWriter(path, 48_000, 2, 16);
            Assert.Throws<ArgumentException>(() => writer.Write(new byte[3], 0, 3));
        }
        finally
        {
            File.Delete(path);
        }
    }
}
