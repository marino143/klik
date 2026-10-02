# Manual stop investigation (2026-10-02)

## Scope and result

Investigated v0.2.9 build 11: Stop worked early, appeared not to work near minute 90, visible counter kept advancing, recording reportedly 32 GB. No user recording was opened, no running app was stopped or replaced, and no release was published.

**The reported capture failure is not reproduced.** Do not describe this patch as a proven timer/capture fix. The confirmed defect is misleading stop feedback: the control bar kept blinking and updating until both screen capture shutdown and MP4 finalization returned. It could therefore appear to keep recording after accepting Stop. This patch immediately shows “Stopping…” and disables recording controls when the coordinator accepts either stop source. It does not claim capture has already ended.

## Trace and evidence

- Native NSButton targets its owning RecordingControlBar via stopTapped, which calls onStop; the coordinator retains the bar. No delayed target replacement or duration-dependent target exists.
- Coordinator permits stop when recorder.isRecording and not isStoppingRecording. It sets the latter synchronously, then awaits recorder.stopRecording in a task. No timer/deadline condition gates manual stop.
- Recorder checks starting/finishing state, cancels the stop timer before the first suspension, stops microphone, awaits SCStream.stopCapture, marks inputs finished on the writer queue, then awaits AVAssetWriter.finishWriting. Duplicate coordinator requests are ignored. A stale timer task is rejected by generation token.
- Auto-stop timer uses common run-loop modes. Display ticker uses default mode: it can pause during mouse tracking, but cannot disable the button or make manual stop wait for the deadline. No run-loop change was justified.
- Label displays either countdown or elapsed time, not both. At 90 minutes elapsed it is 90:00; maximum supported countdown is 1440:00 left. Tests exercised these and smaller countdowns, native hit testing at all three buttons, containment/non-overlap, and Stop performClick. Baseline Stop worked before source changes, including maximum countdown width. No confirmed long-duration overlap.
- Legacy-feedback regression models accepted Stop with actual timer cancellation and pending finalization. After cancellation the still-active bar changes from countdown to advancing elapsed time (90:01). Thus an advancing counter by itself does NOT prove capture was still running. If the user specifically saw the countdown continue downward, that would be different evidence: an accepted recorder stop cancels that countdown.
- New diagnostics distinguish coordinator request/guard, timer expiry, accepted stop, microphone shutdown, screen shutdown, and MP4 finalization. They log phase timing/status, not recording contents. Existing audio-processing HUD follows capture finalization.

## 32 GB / long-session considerations

Size alone does not identify a stop fault. 32 decimal GB over 90 minutes is about 47.4 Mbps; native/high/60 can request up to 80 Mbps. This is compatible with supported settings, not evidence of malformed encoding. Actual settings/length were not inspected.

The recorder streams media to AVAssetWriter, uses one-second movie fragments and network optimization. Finalization is asynchronous but may take time on a large file. Microphone shutdown and queue.sync are synchronous on the main actor; a persistently advancing timer argues against a continuous main-thread stall during the observed period, but does not exclude transient stalls. No real 90-minute/32-GB capture benchmark was performed.

Post-capture audio mixing is a separate, real scaling risk: EchoCancellingMixer decodes whole 48-kHz mono float tracks into arrays, aligns them, builds cleaned and mixed arrays, and writes a new movie with video passthrough. One 90-minute float track alone is about 1.04 GB (decimal); several arrays coexist. It can create substantial memory and disk pressure. The non-main-actor async mixer runs after capture/finalization and after dismissal of the bar, so it does not establish why an earlier Stop click failed. No speculative audio rewrite or recording-file deletion change is included here.

## Regression boundaries

Tests cover actual AppKit target/action and view hit testing, simulated 90-minute display, maximum countdown, Stop before deadline, cancellation, stale queued timeout against a replacement session, duplicate button click after accepted stop, and persistent stopping feedback. They do not synthesize global mouse events or prove ScreenCaptureKit/AVAssetWriter behavior under 32-GB load. Production coordinator wiring is source-traced; the native-action tests use a controlled callback rather than a live capture coordinator.

To settle the original incident, collect stop-phase diagnostics from a future reproduction (or a separately authorized synthetic long capture), plus whether the counter was elapsed counting up or countdown counting down. Do not force-quit a potentially finalizing recording or overwrite it.

## UI direction and scoped gate

Reading this as: existing native macOS recording controls for Klik users, preserving native compact style; ENERGY 1 / RHYTHM 1 / MOTION 1 for the changed stopping state.

- PASS, feedback: native label says Stopping… immediately on accepted request; blink ceases and controls disable. No new decoration, colors for branding, assets, navigation, or theme.
- PASS, purpose: existing typography/layout retained for stable controls; neutral indicator distinguishes stopping from live recording without claiming completion.
- PASS, layout/action: regression tests exercise long labels, hit testing and native target/action; no control overlap at supported durations.
- PASS, honesty: no claim of reproduced 90-minute capture fault or completed capture while shutdown is pending.
- PASS, build: direct signed app and Store compilation checked separately; no install or release. Existing full-app accessibility/theme behavior is outside this small state-feedback change, not represented as a new comprehensive audit.
