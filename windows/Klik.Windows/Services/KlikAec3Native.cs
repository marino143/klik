using System.Runtime.InteropServices;

namespace Klik.Windows.Services;

internal sealed class KlikAec3Native : IDisposable
{
    private const int SampleRate = 48_000;
    public const int FrameSamples = SampleRate / 100;

    [DllImport("KlikAec3", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint klik_aec3_create(int sampleRateHz);

    [DllImport("KlikAec3", CallingConvention = CallingConvention.Cdecl)]
    private static extern void klik_aec3_destroy(nint processor);

    [DllImport("KlikAec3", CallingConvention = CallingConvention.Cdecl)]
    private static extern nuint klik_aec3_frame_size(nint processor);

    [DllImport("KlikAec3", CallingConvention = CallingConvention.Cdecl)]
    private static extern int klik_aec3_process_frame(
        nint processor,
        float[] render,
        float[] capture,
        float[] output,
        nuint sampleCount);

    private nint _processor;

    public KlikAec3Native()
    {
        _processor = klik_aec3_create(SampleRate);
        if (_processor == 0 || klik_aec3_frame_size(_processor) != FrameSamples)
            throw new InvalidOperationException("Klik AEC3 could not be initialized.");
    }

    public void Process(float[] render, float[] capture, float[] output)
    {
        if (_processor == 0) throw new ObjectDisposedException(nameof(KlikAec3Native));
        if (render.Length != FrameSamples || capture.Length != FrameSamples || output.Length != FrameSamples)
            throw new ArgumentException("AEC3 requires one 10 ms frame at 48 kHz.");
        if (klik_aec3_process_frame(_processor, render, capture, output, FrameSamples) != 1)
            throw new InvalidOperationException("Klik AEC3 rejected an audio frame.");
    }

    public void Dispose()
    {
        if (_processor == 0) return;
        klik_aec3_destroy(_processor);
        _processor = 0;
    }
}
