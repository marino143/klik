using System.IO;
using System.Text;

namespace Klik.Windows.Services;

internal sealed class PcmWaveWriter : IDisposable
{
    private readonly FileStream _stream;
    private readonly BinaryWriter _writer;
    private readonly short _blockAlign;
    private long _dataLength;
    private bool _disposed;

    public PcmWaveWriter(string path, int sampleRate, short channels, short bitsPerSample)
    {
        _stream = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read);
        _writer = new BinaryWriter(_stream, Encoding.ASCII, leaveOpen: true);
        _blockAlign = (short)(channels * bitsPerSample / 8);
        var byteRate = sampleRate * _blockAlign;

        _writer.Write(Encoding.ASCII.GetBytes("RIFF"));
        _writer.Write(0);
        _writer.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
        _writer.Write(16);
        _writer.Write((short)1);
        _writer.Write(channels);
        _writer.Write(sampleRate);
        _writer.Write(byteRate);
        _writer.Write(_blockAlign);
        _writer.Write(bitsPerSample);
        _writer.Write(Encoding.ASCII.GetBytes("data"));
        _writer.Write(0);
    }

    public void Write(byte[] buffer, int offset, int count)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (count % _blockAlign != 0) throw new ArgumentException("PCM data must contain complete frames.", nameof(count));
        _writer.Write(buffer, offset, count);
        _dataLength += count;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _writer.Flush();
        _stream.Position = 4;
        _writer.Write(checked((int)(36 + _dataLength)));
        _stream.Position = 40;
        _writer.Write(checked((int)_dataLength));
        _writer.Dispose();
        _stream.Dispose();
    }
}
