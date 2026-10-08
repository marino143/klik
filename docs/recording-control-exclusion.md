# Recording control exclusion

## Native approach

No masking, hiding, moving the controls offscreen, or change to Stop behavior.

macOS: ScreenCaptureKit excludes the current process with an excluding-applications filter. The recorder obtains a fresh shareable-content snapshot with onScreenWindowsOnly=false; it no longer relies on the coordinator's older onscreen-only snapshot or bundle-ID matching. Application exclusion covers windows created later, including the recording bar presented after startCapture. If the process is absent, start fails explicitly rather than silently recording controls. Optional window exclusions from other processes are retained; own-window exceptions are removed because ScreenCaptureKit would otherwise INCLUDE them. NSWindow.sharingType is not used as the solution.

All Klik windows from this process are excluded, not just the bar. Other applications remain included, along with their system audio. capturesAudio, the separate microphone pipeline, region sourceRect, quality settings, diagnostics, and timer handling are unchanged. macOS currently exposes full-display and region video recording; window capture is a screenshot path and was left unchanged (there is no existing window-video path to modify).

Windows: the recording controls live in MainWindow's top-level WPF HWND, not a separate bar window. Before each recording, EnsureHandle obtains the current HWND and SetWindowDisplayAffinity sets WDA_EXCLUDEFROMCAPTURE (0x11). GetWindowDisplayAffinity verifies it. Affinity is retained for the HWND lifetime, including asynchronous Stop/discard finalization, so controls cannot flash into trailing frames. It is reapplied on every start, not cached against a potentially stale HWND. Consequently the entire Klik main window stays excluded from compatible capture APIs after the first recording, including while idle. Desktop visibility, input and accessibility are unchanged.

ScreenRecorderLib 7.0.1 explicitly uses WindowsGraphicsCapture for display/region; window sources use its window capture path. Audio remains WASAPI loopback plus the existing microphone/AEC path. Windows 10 2004/build 19041+, desktop composition and successful set/readback are required. Unsupported states fail before recording begins using the existing error presentation. There is no WDA_MONITOR fallback (that older mode leaves a blank rectangle). OS-native exclusion is intended to show underlying content instead of a black mask; GPU/OS runtime verification remains necessary, and affinity is not a security guarantee.

References inspected: installed Apple ScreenCaptureKit SCStream.h documentation for excludingApplications/exceptingWindows; https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity . No new capture dependency.

## Verification

- Swift policy tests cover PID identity with no visible windows and no bundle ID, missing-process failure, and exception inversion (cannot reinclude own controls).
- Existing native Stop action/mouse tests, timer, quality and idle-resource tests remain in the full suite.
- Windows injectable policy tests cover exact 0x11 affinity, successive HWNDs, old OS/zero HWND/no compositor, native errors, and rejection of WDA_NONE/WDA_MONITOR readback.
- No user desktop or audio was captured. No app was installed, launched, quit, or restarted; native UI tests use test-owned windows only. No release was published.

### Local results (2026-10-08)

- `swift test`: 30 tests passed, zero failures (includes 3 new exclusion tests).
- `swift build -c release`: passed. Existing AudioMixer deprecation/concurrency warnings remain.
- .NET SDK 8.0.425, isolated under build/control-exclusion-validation/dotnet-sdk: test project Release run passed all 11 cases (7 new exclusion cases); WPF app Release x64 cross-build passed with zero warnings/errors.
- `git diff --check`: passed.
- Logs: build/control-exclusion-validation/{swift-test,swift-release,dotnet-test,dotnet-build}.log.
- Mac executable: .build/arm64-apple-macosx/release/Klik.
- Windows assembly: windows/Klik.Windows/bin/x64/Release/net8.0-windows10.0.19041.0/win-x64/Klik.dll.

## Runtime release gate (not performed here)

On a consented synthetic desktop/test account, cover a known colored/checkered background with the controls. Verify recorded pixels show the underlying pattern, not controls or a black rectangle. Test full display, region intersecting the controls, Windows window recording, multiple displays, late-created controls, Stop/cancel and repeated sessions. Include another application's test tone and a synthetic microphone source to verify audio. On Windows include build 19041 and Windows 11, different scaling/GPU setups, and affinity failures. On macOS include menu-bar-only launch with no preexisting Klik windows. Unit/build success does not establish compositor pixel correctness.
