# Klik for Windows

Windows 10 port of Klik. This is a native WPF application, not an Electron wrapper.

## Current preview

- Region, display, and window screenshots to PNG
- Region, display, and window recording to H.264 MP4
- Windows Graphics Capture / DXGI capture through ScreenRecorderLib
- System audio through WASAPI loopback
- Optional default microphone capture
- Pause, resume, stop, and discard
- Global shortcuts: `Win+Shift+2`, `Win+Shift+3`, `Win+Shift+4`, `Win+Shift+5`
- Configurable output folder

The Windows capture pipeline builds and packages successfully, but it still needs a real Windows 10 runtime pass before public distribution. Speaker mode currently uses the same Windows audio inputs with a slightly lower microphone gain. The macOS WebRTC AEC3 post-processing pipeline has not yet been connected to the Windows encoder, so speaker recordings can still contain room echo. Headphones mode is the safe preview mode.

## Requirements

- Windows 10 version 2004 (build 19041) or newer
- x64 CPU
- Media Foundation (included with standard Windows editions)
- Media Feature Pack on Windows N/KN

The self-contained package includes the .NET 8 Desktop runtime. Screen recording uses the MIT-licensed [ScreenRecorderLib](https://github.com/sskodje/ScreenRecorderLib).

## Build

Open PowerShell in this folder:

```powershell
./build.ps1
```

Create a self-contained preview package:

```powershell
./package.ps1
```

The unpacked app is written to `artifacts/Klik-Windows-preview`. Run `Klik.exe`.

## Project layout

- `Klik.Windows`: WPF application and capture services
- `Klik.Windows.Tests`: cross-platform tests for capture configuration models
- `build.ps1`: restore, build, and tests
- `package.ps1`: self-contained Windows x64 publish

## Release gate

Do not publish this preview until it has been exercised on Windows 10 with:

1. A display, region, and window recording
2. System audio only
3. System audio plus microphone with headphones
4. Speaker playback after the AEC3 path is connected
5. Pause/resume and discard
6. 100%, 125%, and 150% display scaling
7. Windows N with Media Feature Pack, or a documented unsupported-state message
