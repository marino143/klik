using Klik.Windows.Models;
using ScreenRecorderLib;
using System.IO;

namespace Klik.Windows.Services;

public sealed class RecorderService : IDisposable
{
    private Recorder? _recorder;
    private TaskCompletionSource<string>? _completion;
    private string? _currentPath;
    private bool _discardCurrent;

    public event EventHandler<RecorderStatus>? StatusChanged;
    public event EventHandler<string>? RecordingFailed;

    public RecorderStatus Status => _recorder?.Status ?? RecorderStatus.Idle;

    public Task<string> StartAsync(CaptureTarget target, AudioMode mode, bool microphoneEnabled, string outputFolder)
    {
        if (_recorder is not null && _recorder.Status != RecorderStatus.Idle)
            throw new InvalidOperationException("A recording is already active.");

        Directory.CreateDirectory(outputFolder);
        _currentPath = Path.Combine(outputFolder, $"Klik {DateTime.Now:yyyy-MM-dd HH-mm-ss}.mp4");
        _discardCurrent = false;

        var recordingSource = CreateSource(target);
        var audioSources = new List<AudioSourceBase>();
        var loopback = LoopbackAudioSource.Default;
        if (loopback is not null) audioSources.Add(loopback);
        if (microphoneEnabled)
        {
            var microphone = CaptureAudioSource.Default;
            if (microphone is not null)
            {
                microphone.ForceMono = true;
                microphone.Volume = mode == AudioMode.Speakers ? 0.9f : 1.0f;
                audioSources.Add(microphone);
            }
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

        _completion = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        _recorder = Recorder.CreateRecorder(options);
        _recorder.OnStatusChanged += OnStatusChanged;
        _recorder.OnRecordingComplete += OnRecordingComplete;
        _recorder.OnRecordingFailed += OnRecordingFailed;
        _recorder.Record(_currentPath);
        return _completion.Task;
    }

    public void Pause() => _recorder?.Pause();
    public void Resume() => _recorder?.Resume();
    public void Stop() => _recorder?.Stop();

    public void Cancel()
    {
        _discardCurrent = true;
        _recorder?.Stop();
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

    private void OnStatusChanged(object? sender, RecordingStatusEventArgs e)
        => StatusChanged?.Invoke(this, e.Status);

    private void OnRecordingComplete(object? sender, RecordingCompleteEventArgs e)
    {
        if (_discardCurrent)
        {
            try { File.Delete(e.FilePath); } catch { }
        }
        _completion?.TrySetResult(e.FilePath);
        CleanupRecorder();
    }

    private void OnRecordingFailed(object? sender, RecordingFailedEventArgs e)
    {
        _completion?.TrySetException(new InvalidOperationException(e.Error));
        RecordingFailed?.Invoke(this, e.Error);
        CleanupRecorder();
    }

    private void CleanupRecorder()
    {
        if (_recorder is null) return;
        _recorder.OnStatusChanged -= OnStatusChanged;
        _recorder.OnRecordingComplete -= OnRecordingComplete;
        _recorder.OnRecordingFailed -= OnRecordingFailed;
        _recorder.Dispose();
        _recorder = null;
        _currentPath = null;
        _discardCurrent = false;
    }

    public void Dispose()
    {
        if (_recorder?.Status is RecorderStatus.Recording or RecorderStatus.Paused)
            _recorder.Stop();
        CleanupRecorder();
    }
}
