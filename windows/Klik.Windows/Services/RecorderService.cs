using Klik.Windows.Models;
using ScreenRecorderLib;
using System.IO;

namespace Klik.Windows.Services;

public sealed class RecorderService : IDisposable
{
    private readonly object _audioWriteLock = new();
    private Recorder? _recorder;
    private TaskCompletionSource<string>? _completion;
    private string? _finalPath;
    private string? _sessionDirectory;
    private bool _discardCurrent;
    private bool _speakerProcessingEnabled;
    private string? _loopbackSourceId;
    private string? _microphoneSourceId;
    private FileStream? _loopbackPcm;
    private FileStream? _microphonePcm;

    public event EventHandler<RecorderStatus>? StatusChanged;
    public event EventHandler<string>? RecordingFailed;

    public RecorderStatus Status => _recorder?.Status ?? RecorderStatus.Idle;

    public static void CleanupAbandonedSessions()
    {
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Klik", "Temp");
        if (!Directory.Exists(root)) return;
        foreach (var directory in Directory.EnumerateDirectories(root))
        {
            try
            {
                if (Directory.GetLastWriteTimeUtc(directory) < DateTime.UtcNow.AddHours(-6))
                    Directory.Delete(directory, recursive: true);
            }
            catch { }
        }
    }

    public Task<string> StartAsync(CaptureTarget target, AudioMode mode, bool microphoneEnabled, string outputFolder)
    {
        if (_recorder is not null && _recorder.Status != RecorderStatus.Idle)
            throw new InvalidOperationException("A recording is already active.");

        Directory.CreateDirectory(outputFolder);
        _finalPath = UniqueOutputPath(outputFolder);
        _discardCurrent = false;
        _speakerProcessingEnabled = mode == AudioMode.Speakers && microphoneEnabled;
        if (_speakerProcessingEnabled)
            SpeakerAudioProcessor.EnsureRuntimeAvailable();

        _sessionDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Klik", "Temp", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_sessionDirectory);
        var capturePath = Path.Combine(_sessionDirectory, "capture.mp4");

        if (_speakerProcessingEnabled)
        {
            _loopbackPcm = NewPcmStream("loopback.pcm");
            _microphonePcm = NewPcmStream("microphone.pcm");
        }

        var recordingSource = CreateSource(target);
        var audioSources = new List<AudioSourceBase>();
        var loopback = LoopbackAudioSource.Default;
        if (loopback is not null)
        {
            _loopbackSourceId = loopback.ID;
            audioSources.Add(loopback);
        }

        CaptureAudioSource? microphone = null;
        if (microphoneEnabled)
        {
            microphone = CaptureAudioSource.Default;
            if (microphone is not null)
            {
                microphone.ForceMono = true;
                microphone.Volume = 1.0f;
                _microphoneSourceId = microphone.ID;
                audioSources.Add(microphone);
            }
        }

        if (_speakerProcessingEnabled && (loopback is null || microphone is null))
        {
            CloseAudioStreams();
            DeleteSessionDirectory();
            throw new InvalidOperationException("Speaker mode needs both a playback device and a microphone.");
        }

        var options = new RecorderOptions
        {
            SourceOptions = new SourceOptions
            {
                RecordingSources = new List<RecordingSourceBase> { recordingSource }
            },
            AudioOptions = new AudioOptions
            {
                IsAudioEnabled = audioSources.Count > 0,
                IsAudioPacketPreviewEnabled = _speakerProcessingEnabled,
                Bitrate = AudioBitrate.bitrate_128kbps,
                Channels = AudioChannels.Stereo,
                AudioSources = audioSources
            },
            VideoEncoderOptions = new VideoEncoderOptions
            {
                Framerate = 30,
                Bitrate = 6_000_000,
                IsHardwareEncodingEnabled = true,
                IsMp4FastStartEnabled = true,
                IsFragmentedMp4Enabled = true,
                Encoder = new H264VideoEncoder
                {
                    EncoderProfile = H264Profile.High,
                    BitrateMode = H264BitrateControlMode.UnconstrainedVBR
                }
            },
            OutputOptions = new OutputOptions
            {
                RecorderMode = RecorderMode.Video
            },
            MouseOptions = new MouseOptions
            {
                IsMousePointerEnabled = true
            }
        };

        try
        {
            _completion = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            _recorder = Recorder.CreateRecorder(options);
            _recorder.OnStatusChanged += OnStatusChanged;
            _recorder.OnRecordingComplete += OnRecordingComplete;
            _recorder.OnRecordingFailed += OnRecordingFailed;
            if (_speakerProcessingEnabled)
                _recorder.OnAudioPacketRecorded += OnAudioPacketRecorded;
            _recorder.Record(capturePath);
            return _completion.Task;
        }
        catch
        {
            CloseAudioStreams();
            CleanupRecorder();
            DeleteSessionDirectory();
            throw;
        }
    }

    public void Pause() => _recorder?.Pause();
    public void Resume() => _recorder?.Resume();
    public void Stop() => _recorder?.Stop();

    public void Cancel()
    {
        _discardCurrent = true;
        _recorder?.Stop();
    }

    private FileStream NewPcmStream(string name)
        => new(Path.Combine(_sessionDirectory!, name), FileMode.CreateNew, FileAccess.Write, FileShare.Read,
            bufferSize: 64 * 1024, FileOptions.SequentialScan);

    private static string UniqueOutputPath(string outputFolder)
    {
        var stem = $"Klik {DateTime.Now:yyyy-MM-dd HH-mm-ss}";
        var path = Path.Combine(outputFolder, stem + ".mp4");
        for (var suffix = 2; File.Exists(path); suffix++)
            path = Path.Combine(outputFolder, $"{stem} {suffix}.mp4");
        return path;
    }

    private static RecordingSourceBase CreateSource(CaptureTarget target)
    {
        if (target.Kind == CaptureKind.Window)
            return new WindowRecordingSource(target.WindowHandle)
            {
                IsCursorCaptureEnabled = true,
                IsBorderRequired = false
            };

        var display = new DisplayRecordingSource(target.DisplayDeviceName)
        {
            RecorderApi = RecorderApi.WindowsGraphicsCapture,
            IsCursorCaptureEnabled = true,
            IsBorderRequired = false
        };
        if (target.Region is { } region)
            display.SourceRect = new ScreenRect(region.X, region.Y, region.Width, region.Height);
        return display;
    }

    private void OnAudioPacketRecorded(object? sender, AudioDataRecordedEventArgs e)
    {
        if (!_speakerProcessingEnabled || e.AudioData?.Sources is null) return;
        lock (_audioWriteLock)
        {
            foreach (var source in e.AudioData.Sources)
            {
                if (source.Data is not { Length: > 0 }) continue;
                if (source.Id == _loopbackSourceId)
                    _loopbackPcm?.Write(source.Data);
                else if (source.Id == _microphoneSourceId)
                    _microphonePcm?.Write(source.Data);
            }
        }
    }

    private void OnStatusChanged(object? sender, RecordingStatusEventArgs e)
        => StatusChanged?.Invoke(this, e.Status);

    private async void OnRecordingComplete(object? sender, RecordingCompleteEventArgs e)
    {
        try
        {
            CloseAudioStreams();
            if (_discardCurrent)
            {
                _completion?.TrySetCanceled();
                return;
            }

            if (_speakerProcessingEnabled)
            {
                await SpeakerAudioProcessor.ProcessAsync(
                    e.FilePath,
                    Path.Combine(_sessionDirectory!, "loopback.pcm"),
                    Path.Combine(_sessionDirectory!, "microphone.pcm"),
                    _finalPath!);
            }
            else
            {
                File.Move(e.FilePath, _finalPath!, overwrite: true);
            }
            _completion?.TrySetResult(_finalPath!);
        }
        catch (Exception exception)
        {
            _completion?.TrySetException(exception);
            RecordingFailed?.Invoke(this, exception.Message);
        }
        finally
        {
            CleanupRecorder();
            DeleteSessionDirectory();
        }
    }

    private void OnRecordingFailed(object? sender, RecordingFailedEventArgs e)
    {
        CloseAudioStreams();
        _completion?.TrySetException(new InvalidOperationException(e.Error));
        RecordingFailed?.Invoke(this, e.Error);
        CleanupRecorder();
        DeleteSessionDirectory();
    }

    private void CloseAudioStreams()
    {
        lock (_audioWriteLock)
        {
            _loopbackPcm?.Dispose();
            _microphonePcm?.Dispose();
            _loopbackPcm = null;
            _microphonePcm = null;
        }
    }

    private void CleanupRecorder()
    {
        if (_recorder is not null)
        {
            _recorder.OnStatusChanged -= OnStatusChanged;
            _recorder.OnRecordingComplete -= OnRecordingComplete;
            _recorder.OnRecordingFailed -= OnRecordingFailed;
            _recorder.OnAudioPacketRecorded -= OnAudioPacketRecorded;
            _recorder.Dispose();
        }
        _recorder = null;
        _finalPath = null;
        _loopbackSourceId = null;
        _microphoneSourceId = null;
        _speakerProcessingEnabled = false;
        _discardCurrent = false;
    }

    private void DeleteSessionDirectory()
    {
        var directory = _sessionDirectory;
        _sessionDirectory = null;
        if (string.IsNullOrWhiteSpace(directory)) return;
        try { Directory.Delete(directory, recursive: true); } catch { }
    }

    public void Dispose()
    {
        if (_recorder?.Status is RecorderStatus.Recording or RecorderStatus.Paused)
            _recorder.Stop();
        CloseAudioStreams();
        CleanupRecorder();
        DeleteSessionDirectory();
    }
}
