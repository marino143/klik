using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace Klik.Windows.Services;

internal static class SpeakerAudioProcessor
{
    private const int SampleRate = 48_000;
    private const short Channels = 2;
    private const short BitsPerSample = 16;
    private const int BytesPerStereoFrame = Channels * BitsPerSample / 8;
    private const int AecFrameBytes = KlikAec3Native.FrameSamples * BytesPerStereoFrame;

    public static void EnsureRuntimeAvailable()
    {
        var aecPath = Path.Combine(AppContext.BaseDirectory, "KlikAec3.dll");
        if (!File.Exists(aecPath) || !NativeLibrary.TryLoad(aecPath, out var handle))
            throw new InvalidOperationException("Speaker mode needs KlikAec3.dll. Reinstall the complete Klik package.");
        NativeLibrary.Free(handle);

        if (ResolveFfmpeg() is null)
            throw new InvalidOperationException("Speaker mode needs the bundled FFmpeg audio muxer. Reinstall the complete Klik package.");
    }

    public static async Task ProcessAsync(
        string capturedMp4,
        string loopbackPcm,
        string microphonePcm,
        string outputMp4)
    {
        var workDirectory = Path.GetDirectoryName(capturedMp4)
            ?? throw new InvalidOperationException("Recording work directory is missing.");
        var mixedWav = Path.Combine(workDirectory, "speaker-clean.wav");
        var muxedMp4 = Path.Combine(workDirectory, "speaker-final.mp4");

        await Task.Run(() => CreateCleanMix(loopbackPcm, microphonePcm, mixedWav));
        await MuxAsync(capturedMp4, mixedWav, muxedMp4);
        Directory.CreateDirectory(Path.GetDirectoryName(outputMp4)!);
        File.Move(muxedMp4, outputMp4, overwrite: true);
    }

    internal static void CreateCleanMix(string loopbackPcm, string microphonePcm, string outputWav)
    {
        using var renderStream = File.OpenRead(loopbackPcm);
        using var captureStream = File.OpenRead(microphonePcm);
        using var writer = new PcmWaveWriter(outputWav, SampleRate, Channels, BitsPerSample);
        using var aec = new KlikAec3Native();

        var renderBytes = new byte[AecFrameBytes];
        var captureBytes = new byte[AecFrameBytes];
        var outputBytes = new byte[AecFrameBytes];
        var renderMono = new float[KlikAec3Native.FrameSamples];
        var captureMono = new float[KlikAec3Native.FrameSamples];
        var cleanMono = new float[KlikAec3Native.FrameSamples];

        while (true)
        {
            var renderRead = ReadFrame(renderStream, renderBytes);
            var captureRead = ReadFrame(captureStream, captureBytes);
            if (renderRead == 0 && captureRead == 0) break;

            StereoPcm16ToMono(renderBytes, renderMono);
            StereoPcm16ToMono(captureBytes, captureMono);
            aec.Process(renderMono, captureMono, cleanMono);
            MixToStereo(renderBytes, cleanMono, outputBytes);

            var validBytes = Math.Max(renderRead, captureRead);
            writer.Write(outputBytes, 0, validBytes);
            Array.Clear(renderBytes);
            Array.Clear(captureBytes);
        }
    }

    private static int ReadFrame(Stream stream, byte[] buffer)
    {
        var total = 0;
        while (total < buffer.Length)
        {
            var read = stream.Read(buffer, total, buffer.Length - total);
            if (read == 0) break;
            total += read;
        }
        if (total < buffer.Length) Array.Clear(buffer, total, buffer.Length - total);
        return total - total % BytesPerStereoFrame;
    }

    private static void StereoPcm16ToMono(byte[] stereo, float[] mono)
    {
        for (var frame = 0; frame < mono.Length; frame++)
        {
            var offset = frame * BytesPerStereoFrame;
            var left = BitConverter.ToInt16(stereo, offset);
            var right = BitConverter.ToInt16(stereo, offset + 2);
            mono[frame] = ((left + right) * 0.5f) / short.MaxValue;
        }
    }

    private static void MixToStereo(byte[] renderStereo, float[] cleanMicrophone, byte[] output)
    {
        for (var frame = 0; frame < cleanMicrophone.Length; frame++)
        {
            var offset = frame * BytesPerStereoFrame;
            var left = BitConverter.ToInt16(renderStereo, offset);
            var right = BitConverter.ToInt16(renderStereo, offset + 2);
            var microphone = cleanMicrophone[frame] * short.MaxValue * 0.9f;
            WriteInt16(output, offset, Clamp(left + microphone));
            WriteInt16(output, offset + 2, Clamp(right + microphone));
        }
    }

    private static short Clamp(float sample)
        => (short)Math.Clamp(MathF.Round(sample), short.MinValue, short.MaxValue);

    private static void WriteInt16(byte[] output, int offset, short value)
    {
        output[offset] = (byte)(value & 0xff);
        output[offset + 1] = (byte)((value >> 8) & 0xff);
    }

    private static async Task MuxAsync(string capturedMp4, string mixedWav, string outputMp4)
    {
        var ffmpeg = ResolveFfmpeg()
            ?? throw new InvalidOperationException("The bundled FFmpeg audio muxer is missing.");
        var startInfo = new ProcessStartInfo
        {
            FileName = ffmpeg,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true
        };
        foreach (var argument in new[]
        {
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", capturedMp4,
            "-i", mixedWav,
            "-map", "0:v:0",
            "-map", "1:a:0",
            "-c:v", "copy",
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",
            outputMp4
        }) startInfo.ArgumentList.Add(argument);

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("FFmpeg could not be started.");
        var errorTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var error = await errorTask;
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"Speaker audio processing failed: {SafeError(error)}");
    }

    private static string? ResolveFfmpeg()
    {
        var bundled = Path.Combine(AppContext.BaseDirectory, "tools", "ffmpeg.exe");
        if (File.Exists(bundled)) return bundled;
        return OperatingSystem.IsWindows() ? "ffmpeg.exe" : null;
    }

    private static string SafeError(string error)
    {
        var compact = string.Join(' ', error.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries));
        return compact.Length <= 400 ? compact : compact[..400];
    }
}
