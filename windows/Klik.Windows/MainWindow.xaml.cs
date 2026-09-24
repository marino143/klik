using Klik.Windows.Models;
using Klik.Windows.Services;
using ScreenRecorderLib;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Klik.Windows;

public partial class MainWindow : Window
{
    private readonly AppSettings _settings = AppSettings.Load();
    private readonly RecorderService _recorder = new();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private DateTime _recordingStartedAt;
    private AudioMode _audioMode = AudioMode.Speakers;
    private HotkeyService? _hotkeys;
    private bool _isPaused;
    private bool _cancelRequested;

    public MainWindow()
    {
        InitializeComponent();
        OutputFolderText.Text = _settings.OutputFolder;
        _timer.Tick += (_, _) =>
        {
            var elapsed = DateTime.Now - _recordingStartedAt;
            TimerText.Text = elapsed.ToString(elapsed.TotalHours >= 1 ? @"hh\:mm\:ss" : @"mm\:ss");
        };
        _recorder.StatusChanged += Recorder_StatusChanged;
        _recorder.RecordingFailed += (_, error) => Dispatcher.Invoke(() => ShowError(error));
    }

    private Forms.Screen CurrentScreen => Forms.Screen.PrimaryScreen
        ?? throw new InvalidOperationException("No display is available.");

    private CaptureTarget ScreenTarget()
        => new(CaptureKind.Display, CurrentScreen.DeviceName, Label: CurrentScreen.DeviceName);

    private CaptureTarget? RegionTarget()
    {
        Hide();
        var selector = new RegionSelectorWindow(CurrentScreen);
        var accepted = selector.ShowDialog() == true;
        Show();
        Activate();
        return accepted && selector.SelectedRegion is { } region
            ? new CaptureTarget(CaptureKind.Region, CurrentScreen.DeviceName,
                new CaptureRect(region.X, region.Y, region.Width, region.Height), Label: "Region")
            : null;
    }

    private CaptureTarget? WindowTarget()
    {
        var picker = new WindowPickerWindow { Owner = this };
        if (picker.ShowDialog() != true || picker.SelectedWindow is not { } window) return null;
        return new CaptureTarget(CaptureKind.Window, CurrentScreen.DeviceName,
            WindowHandle: window.Handle, Label: window.Title);
    }

    private void CaptureScreen_Click(object sender, RoutedEventArgs e) => CaptureScreenshot(ScreenTarget());
    private void CaptureRegion_Click(object sender, RoutedEventArgs e)
    {
        if (RegionTarget() is { } target) CaptureScreenshot(target);
    }
    private void CaptureWindow_Click(object sender, RoutedEventArgs e)
    {
        if (WindowTarget() is { } target) CaptureScreenshot(target);
    }

    private void CaptureScreenshot(CaptureTarget target)
    {
        try
        {
            Hide();
            Thread.Sleep(140);
            var path = ScreenshotService.Capture(target, _settings.OutputFolder);
            Show();
            Activate();
            StatusText.Text = $"Saved {Path.GetFileName(path)}";
            System.Windows.Clipboard.SetText(path);
        }
        catch (Exception exception)
        {
            Show();
            ShowError(exception.Message);
        }
    }

    private async void RecordScreen_Click(object sender, RoutedEventArgs e) => await StartRecordingAsync(ScreenTarget());
    private async void RecordRegion_Click(object sender, RoutedEventArgs e)
    {
        if (RegionTarget() is { } target) await StartRecordingAsync(target);
    }
    private async void RecordWindow_Click(object sender, RoutedEventArgs e)
    {
        if (WindowTarget() is { } target) await StartRecordingAsync(target);
    }

    private async Task StartRecordingAsync(CaptureTarget target)
    {
        try
        {
            _cancelRequested = false;
            ReadyView.Visibility = Visibility.Collapsed;
            RecordingView.Visibility = Visibility.Visible;
            Topmost = true;
            Height = 390;
            _recordingStartedAt = DateTime.Now;
            _timer.Start();
            var result = await _recorder.StartAsync(
                target, _audioMode, MicrophoneCheck.IsChecked == true, _settings.OutputFolder);
            if (!_cancelRequested)
            {
                ResetAfterRecording();
                StatusText.Text = $"Saved {Path.GetFileName(result)}";
                OpenFolder(result);
            }
        }
        catch (Exception exception)
        {
            ResetAfterRecording();
            ShowError(exception.Message);
        }
    }

    private void Pause_Click(object sender, RoutedEventArgs e)
    {
        if (_isPaused)
        {
            _recorder.Resume();
            PauseButton.Content = "Pause";
        }
        else
        {
            _recorder.Pause();
            PauseButton.Content = "Resume";
        }
        _isPaused = !_isPaused;
    }

    private void Stop_Click(object sender, RoutedEventArgs e) => _recorder.Stop();

    private void CancelRecording_Click(object sender, RoutedEventArgs e)
    {
        _cancelRequested = true;
        _recorder.Cancel();
        ResetAfterRecording();
        StatusText.Text = "Recording discarded";
    }

    private void Recorder_StatusChanged(object? sender, RecorderStatus status)
    {
        Dispatcher.Invoke(() =>
        {
            if (status == RecorderStatus.Finishing)
                TimerText.Text = "Saving…";
        });
    }

    private void ResetAfterRecording()
    {
        Dispatcher.Invoke(() =>
        {
            _timer.Stop();
            _isPaused = false;
            PauseButton.Content = "Pause";
            Topmost = false;
            Height = 610;
            RecordingView.Visibility = Visibility.Collapsed;
            ReadyView.Visibility = Visibility.Visible;
        });
    }

    private void Speakers_Click(object sender, RoutedEventArgs e)
    {
        _audioMode = AudioMode.Speakers;
        SpeakersButton.Background = System.Windows.Media.Brushes.Black;
        SpeakersButton.Foreground = System.Windows.Media.Brushes.White;
        HeadphonesButton.Background = (System.Windows.Media.Brush)FindResource("LineBrush");
        HeadphonesButton.Foreground = (System.Windows.Media.Brush)FindResource("InkBrush");
        AudioModeHelp.Text = "For recordings played through speakers.";
    }

    private void Headphones_Click(object sender, RoutedEventArgs e)
    {
        _audioMode = AudioMode.Headphones;
        HeadphonesButton.Background = System.Windows.Media.Brushes.Black;
        HeadphonesButton.Foreground = System.Windows.Media.Brushes.White;
        SpeakersButton.Background = (System.Windows.Media.Brush)FindResource("LineBrush");
        SpeakersButton.Foreground = (System.Windows.Media.Brush)FindResource("InkBrush");
        AudioModeHelp.Text = "For recordings made while wearing headphones.";
    }

    private void ChangeFolder_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new Forms.FolderBrowserDialog
        {
            Description = "Choose where Klik saves captures",
            SelectedPath = _settings.OutputFolder,
            UseDescriptionForTitle = true
        };
        if (dialog.ShowDialog() != Forms.DialogResult.OK) return;
        _settings.OutputFolder = dialog.SelectedPath;
        _settings.Save();
        OutputFolderText.Text = _settings.OutputFolder;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _hotkeys = new HotkeyService(this);
        _hotkeys.Register(2, '2', () => CaptureRegion_Click(this, new RoutedEventArgs()));
        _hotkeys.Register(3, '3', () => CaptureScreen_Click(this, new RoutedEventArgs()));
        _hotkeys.Register(4, '4', () => CaptureWindow_Click(this, new RoutedEventArgs()));
        _hotkeys.Register(5, '5', () =>
        {
            Show();
            Activate();
        });
    }

    private static void OpenFolder(string filePath)
    {
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{filePath}\"") { UseShellExecute = true });
        }
        catch { }
    }

    private void ShowError(string message)
    {
        StatusText.Text = "Something went wrong";
        System.Windows.MessageBox.Show(this, message, "Klik", MessageBoxButton.OK, MessageBoxImage.Error);
    }

    private void OnClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        _hotkeys?.Dispose();
        _recorder.Dispose();
    }
}
