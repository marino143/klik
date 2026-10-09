# Recording-start hotfix investigation (2026-10-09)

## Confirmed cause

A fresh accessory/menu-only process with no NSWindow is absent from real ScreenCaptureKit `applications`, even with `onScreenWindowsOnly:false`. The 0.2.10 guard therefore throws before recording starts. The coordinator previously created its bar only after recording successfully started: circular dependency. The older unit fixture supplied an application with zero windows and did not test whether macOS ever supplied that application.

A standalone native probe reproduced the missing PID, then found the PID after constructing a borderless `NSWindow(defer:false)` without ever presenting it. Native XCTest additionally uses the actual `RecordingControlBar`, resolves the real PID, verifies it stays invisible before start, dismisses/releases it, and repeats three times. No pixels or audio are captured by these tests.

## Candidate correction

Both full-display and region paths prepare the actual bar inside the recorder start guard, before enumeration. Presentation remains after successful start; its controls, layout, timer, callbacks, and capture exclusion filter are unchanged. The coordinator releases prepared controls on failed start. Concurrent startup requests are guarded so a rejected request cannot release the first request’s prepared controls. Application resolution uses six fresh snapshots at most, with five 50ms delays for WindowServer registration; API errors/cancellation propagate immediately, and missing identity still fails closed. No empty-exclusion fallback, sharingType workaround, or capture masking.

Apple SDK authority: SCShareableContent.h describes applications as shareable applications, not all running processes. SCStream.h documents excludingApplications/exceptingWindows semantics. The existing all-own-process exclusion remains intact, including future windows.

## Results

- Standalone cold process native probe: reproduced old failure; three materialize/resolve/close attempts pass. `build/hotfix-native-probe.log`.
- Native actual bar test: three prepare/resolve/dismiss/release cycles pass. `build/hotfix-real-control.log`.
- Swift suite with added bounded-retry, fail-closed, API-error, cancellation and retry-after-failure checks: final opt-in run: all 33 tests pass, including native test (`build/hotfix-tests-final.log`). Includes unchanged mouse Stop, timer, quality, AEC and resource tests.
- Production Swift build passes (`build/hotfix-release.log`), existing warnings only.
- No running user Klik was installed, quit, restarted or modified; no permissions changed.

Reproduce native enumeration (existing capture consent required; probe never requests it):

```sh
swiftc -parse-as-library Sources/Klik/RecordingCaptureExclusion.swift scripts/recording-exclusion-probe.swift -o build/recording-exclusion-probe
build/recording-exclusion-probe
KLIK_NATIVE_EXCLUSION_TEST=1 swift test --filter RecordingCaptureNativeTests
```

## Consented production-pipeline video verification (2026-10-09)

After explicit user permission for brief local screen recording without microphone, a separate bounded helper process covered the display with a synthetic green window. The opt-in XCTest invoked the actual VideoRecordingManager, actual RecordingControlBar, ScreenCaptureKit, HEVC writer and stop/finalization code; this was not only the standalone enumeration probe. Both full-display and intersecting-region tests ran in separate cold accessory processes, asserted no initial windows and missing PID before constructing controls, and repeated recording twice.

- Full display 1920x1080: 1.617s and 1.533s finalized movies.
- Region 400x120, intersecting all controls: 1.650s and 1.517s finalized movies.
- In each recording, controls were visible locally, alpha 1, with mouse events enabled; in-process AppKit mouse down/up dispatch to the real Stop button stopped and finalized the real recording. This is not a physical WindowServer/Spaces click test.
- Decoded frame at 0.8 seconds: 1,155 samples across the control footprint per movie all show the underlying green, zero black/bar samples. Initial test thresholds were too narrow for the existing display-P3/HEVC color conversion; observed green values were used with a bounded tolerance that still rejects black and bar colors. No pixel images or movies were uploaded or committed.
- Explicit internal captureAudio=false disables both ScreenCaptureKit audio and microphone engine startup. All four movies had zero audio tracks and zero microphone samples. Default production call sites retain captureAudio=true; audio quality/regressions were NOT runtime-tested.
- Videos and their recovery markers are discarded locally by the test after validation. The synthetic helper exits after at most 60 seconds and is terminated by the runner immediately after tests.
- Logs: build/hotfix-video-display.log and build/hotfix-video-region.log. Source: RecordingVideoNativeTests.swift and scripts/recording-test-background.swift. Run the video test filter alone with KLIK_NATIVE_VIDEO_TEST=1 only after fresh explicit recording consent; set KLIK_NATIVE_VIDEO_REGION=1 for region.

The user's running /Applications/Klik.app was not quit, replaced or installed. No permission changes. Long-recording Stop/RAM, audio, multiple monitors and other OS/GPU combinations are not established by these short tests.

## Direct hotfix release

Live GitHub latest and canonical Sparkle feed were checked at 0.2.10/build 12 before selecting 0.2.11/build 13. Use the existing Developer ID/notarization/stapling/Sparkle pipeline, unchanged established public key, retaining prior feed entries. No Store or Windows changes.
