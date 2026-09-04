<div align="center">
  <img src="docs/icon-256.png" alt="Klik" width="160" />
  <h1>Klik</h1>
  <p><strong>Fast, native macOS screen capture and recording — built for Apple Silicon.</strong></p>

  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
    <img src="https://img.shields.io/badge/Swift-5.10%2B-orange" alt="Swift 5.10+">
    <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-black" alt="Apple Silicon">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
    <a href="https://codigit.io/apps/klik"><img src="https://img.shields.io/badge/codigit.io-Klik-e63946" alt="Klik on codigit.io"></a>
    <a href="https://buymeacoffee.com/marino143"><img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?logo=buymeacoffee&logoColor=black" alt="Buy Me A Coffee"></a>
  </p>
</div>

---

**Klik** is a lightweight macOS screen capture and recording utility inspired by CleanShot.
It lives in your menu bar, captures screenshots and video, and gets out of your way.
No subscription, no telemetry, no Electron — just a 1 MB native `.app` (766 KB binary).

## Features

### 📸 Screenshots
- **Region**, **window**, and **full-screen** capture via ScreenCaptureKit
- **Annotation editor**: rectangle, arrow, text, highlight, gaussian blur, crop
- **Pin to Screen**: float a screenshot above all other windows
- **Auto-copy** to clipboard, **auto-save** to your chosen folder (default: Desktop)

### 🎥 Video Recording
- **Full-screen** or **region** recording, 30 fps HEVC (H.265) MP4 at a 1080p ceiling
- Records **system audio** *and* **microphone** — ideal for capturing meetings
- **Echo cancellation + audio mixdown** run automatically after every recording — the two tracks become one sharing-friendly AAC track, with the speaker echo removed from your mic
- **Convert MP4 → GIF** (12 fps, optimized) in one click
- Floating control bar with REC indicator, live timer, stop and cancel buttons
- Klik's own windows are excluded from the recording automatically

### 🗂 Quick Access Overlay
- After every full-screen or window capture (and every recording), a thumbnail slides in at the bottom-left corner — region captures skip it and open in the editor
- **Drag** it directly into any app — Finder, Slack, Mail, browser uploads, anything that accepts files
- Multiple captures **stack vertically** and stay visible until you dismiss them
- Hover for **Open** / **Edit** / **Save** buttons; right-click for full action menu

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| <kbd>⇧⌘2</kbd> | Capture region — opens straight in the editor |
| <kbd>⇧⌘3</kbd> | Capture full screen |
| <kbd>⇧⌘4</kbd> | Capture window |
| <kbd>⇧⌘5</kbd> | Record video (full screen) |
| <kbd>⇧⌘,</kbd> | Settings |
| <kbd>⇧⌘Q</kbd> | Quit Klik |
| <kbd>Esc</kbd> | Cancel current capture |

## Installation

1. Download `Klik.app.zip` from the [latest release](https://github.com/marino143/klik/releases/latest)
2. Unzip → drag **Klik.app** into `/Applications`
3. Double-click **Klik.app** — it opens straight away, no Gatekeeper warning
   *(signed with a Developer ID certificate, notarised by Apple and stapled)*
4. Look for the camera-viewfinder icon in your menu bar
5. Press <kbd>⇧⌘3</kbd> — macOS will prompt for **Screen Recording** permission. Grant it, then **Quit & Reopen** Klik
6. The first time you record video, you'll also be prompted for **Microphone** access

## Build from Source

Requires macOS 14+, Xcode 15+, Swift 5.10+, Apple Silicon.

```bash
git clone https://github.com/marino143/klik.git
cd klik
./build.sh debug
open build/Klik.app
```

To sign with your own Apple Developer certificate, set `KLIK_SIGN_IDENTITY`:

```bash
KLIK_SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" ./build.sh release
```

`build.sh` signs with an Apple Development certificate, which is fine locally but is rejected by Gatekeeper on any other Mac. `release.sh` builds the distributable instead — Developer ID signature, hardened runtime, notarised by Apple and stapled:

```bash
./release.sh 0.2.0
```

Notarisation needs App Store Connect credentials, stored once in your keychain (see the header of `release.sh`).

To regenerate the app icon from the source script:

```bash
./scripts/build_icns.sh
```

## Architecture

| Layer | Technology |
|---|---|
| Language | Swift 5.10 |
| UI | AppKit + SwiftUI |
| Screenshot | ScreenCaptureKit (`SCScreenshotManager`) |
| Video | ScreenCaptureKit (`SCStream`) + AVAssetWriter |
| Audio | System audio via SCStream, microphone via AVCaptureSession + AVAudioEngine |
| Echo cancellation | Time-domain NLMS adaptive filter with Geigel double-talk detection (Accelerate) |
| Audio mixing | AVAssetReader / AVAssetWriter (passthrough video, PCM sum + AAC re-encode) |
| GIF | ImageIO + AVAssetImageGenerator |
| Global hotkeys | Carbon Event Manager |
| Build | Swift Package Manager + custom `build.sh` / `release.sh` |

**Zero third-party dependencies.** Everything runs on first-party Apple frameworks.

## File Size Estimates

Klik records HEVC (H.265) at a 1080p ceiling — sized for sharing meeting recordings on Slack / Drive / email without a separate re-compression pass. Defaults: ~1.5 bits/pixel, capped at 6 Mbps, plus two AAC audio tracks (128 kbps each).

| What you record | Per minute | 30 min | 1 hour |
|---|---|---|---|
| 1080p region (or any full-screen, downscaled to 1080p) | ~25 MB | ~750 MB | ~1.5 GB |
| 720p region | ~12 MB | ~360 MB | ~720 MB |
| Audio only (both tracks) | ~2 MB | ~60 MB | ~115 MB |

Source captures larger than 1080p (1440p, 4K, 5K) are downscaled by ScreenCaptureKit before encoding, so a full-screen recording on a 5K display still produces a 1080p MP4. This keeps memory use and file size predictable.

## Roadmap

Things on the wishlist that aren't shipped yet:

- H.264 option, for players that still choke on HEVC
- Recording quality presets (Low / Medium / High)
- OCR — copy text out of screenshots
- Scrolling capture
- Cloud upload (S3, custom endpoint)
- Editing annotations after creation
- Drag-out without auto-closing the overlay

Open an issue if you want one of these, or send a PR.

## Why Klik

I use CleanShot every day. I wanted to see how close I could get to its core experience with a Saturday-afternoon side project — no Electron, no third-party deps, just native macOS frameworks on Apple Silicon. The result is a single 766 KB binary that does the things I actually use a screen-capture tool for.

If you find it useful, star the repo. If something's missing, open an issue.

## Support

If Klik saved you a CleanShot subscription or a HandBrake round-trip, consider [buying me a coffee](https://buymeacoffee.com/marino143) ☕. No pressure — the app is and stays free.

## License

MIT — see [LICENSE](LICENSE).

## Author

Built by **Marino Glazar** ([@marino143](https://github.com/marino143)).
