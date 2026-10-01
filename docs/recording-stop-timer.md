# Automatic recording stop

Settings > Recording has an optional, default-off timer. Enter whole minutes and seconds (seconds 0–59), totaling 1 second through 1440 minutes (24 hours). Invalid input disables the saved timer and displays an explanation rather than silently using a previous deadline. Valid changes save immediately and apply to the next recording, without changing resolution, frame rate, or quality.

The duration is snapshotted when recording starts and armed only after ScreenCaptureKit starts successfully. It measures monotonic elapsed recording time, including microphone mute. Klik has no pause/resume recording operation, so there is no paused interval to exclude. System sleep is not a supported recording/pause mode. The recording bar shows minutes:seconds left when enabled, otherwise elapsed time.

Expiry invokes the same coordinator stop action as the bar button, finalizes the MP4, and presents the existing audio processing and save/quick-access flow. It does not discard the file or bypass the existing save UI. Timer callbacks are invalidated on manual stop, cancellation, startup cleanup, unexpected stop, and replacement; session tokens reject queued stale timer callbacks. Finish guards prevent simultaneous stop/finalize operations. Timer resolution is 0.2 seconds; a busy main thread and capture finalization can delay the physical stop, so this is not frame-exact trimming.

## Native design decisions

Reading this as native macOS recording preferences for Klik users, preserving existing AppKit controls, ENERGY 1 / RHYTHM 1 / MOTION 1.

- Native checkbox and labeled text fields match the existing Settings hierarchy and supply standard keyboard focus and accessibility behavior.
- Explicit units and inline validation avoid ambiguous duration entry; no additional modal or decorative icon is needed.
- Existing system typography and semantic colors preserve native light/dark appearance; the existing red recording indicator remains the focal accent.
- A wider recording bar reserves space for the longest valid countdown without crowding audio or stop controls.
- Foundation Timer and monotonic uptime already provide the required behavior; no library or service is necessary.

## Verification

Automated coverage includes validation boundaries, corrupt persistence, default off, enable/disable persistence, one-shot and reentrant timeout, real run-loop delivery, cancellation, replacement, disabled/invalid timers, elapsed-time semantics, native checkbox/field interaction, invalid-input feedback, countdown text, and bar stop callback. Existing quality settings and audio tests remain intact.

Hardware capture, real microphone/system audio, sleep/wake, and end-to-end MP4 finalization under a timer are not exercised by these unit tests. A permission-granted hardware smoke test remains required before release. No installation, upload, or review submission is part of this change.
