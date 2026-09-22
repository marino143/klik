# Klik Mac App Store release

## Product

- Listing name: **Klik: Screen Capture**
- Bundle ID: `hr.codigit.klik`
- Category: Utilities
- Version: 1.0.0 (build 1)
- Business model: paid up front
- Target customer price: **€19.99** in the eurozone
- Privacy: data not collected
- Minimum system: macOS 14, Apple silicon

## Store-specific behavior

- App Sandbox is enabled.
- The user explicitly chooses a save folder; access is persisted as a security-scoped bookmark.
- Sparkle and its update menu are not compiled into this variant.
- Donation and external purchase links are not compiled into this variant.
- Diagnostics export is not compiled into this variant because the direct build reads crash reports outside the sandbox.
- Updates are distributed only by the Mac App Store.

## Build

For a local sandboxed build:

```sh
./build-appstore.sh
```

For distribution, provide an App Store provisioning profile and distribution identities through environment variables. Never commit the profile or private credentials.

## Review notes draft

Klik is a menu bar screen-capture utility. After launch, use the camera-viewfinder icon in the menu bar or Shift-Command-2/3/4/5. macOS asks for Screen Recording permission on first capture and Microphone permission on first recording. Speaker mode uses local WebRTC AEC3 processing to remove room echo. Captures, recordings and diagnostics are never uploaded by the app.
