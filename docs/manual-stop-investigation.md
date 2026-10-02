# Manual stop investigation (2026-10-02)

## Button confirmed: opt-in diagnostic implementation

The user confirms clicking the floating **button**, not the menu/shortcut. Fullscreen/Space state remains unknown. The failure is still unresolved; this change instruments the next boundary, not a speculative capture fix. No visual layout, input policy, stop guards, or capture timing were changed. Existing native AppKit hooks and the existing rotating logger were sufficient; no new dependency or global monitor was needed.

### What the new build records

`RecordingStopDiagnostics` snapshots opt-in `KlikStopDiagnostics` at session start. Each trace line contains a random per-recording UUID, sequence, monotonic milliseconds, and only fixed phase/source names and booleans. It traces bar-window down/up and whether the point is within Stop (not coordinates), window visibility/active-Space/key/app-active flags, native Stop tracking begin/end and action-fired status, target/action and callback presence, coordinator request/accept/reject, automatic deadline, recorder acceptance/rejection, microphone, capture stop, writer queue, writer finalization, and completion/failure. `menuOrShortcut` intentionally groups the existing shared entry point; region menu and automatic expiry are separately tagged.

NSButton consumes release inside its native tracking loop, so the window also observes dequeued mouse-up through `nextEvent`; `sendEvent` alone would miss that boundary. Native behavior is delegated unchanged to super. A release can be logged twice if subsequently dispatched through sendEvent; it is not two physical clicks. No drag/move/keyboard events are recorded, no event taps/monitors, no screenshots, media, filenames, private titles, error descriptions, or secrets are added to this trace.

Storage uses the existing async DiagnosticsLogger, not NSLog: `klik.log` plus five rotated archives, nominally 1 MB each (~6 MB total). Fixed short trace lines cannot create oversized entries. Existing unrelated logger messages and export contents are unchanged and are not claimed to be content-free. The logger is best-effort: disk failure, crash before queued writes, or rotation can lose evidence. No missing log entry alone proves WindowServer interception.

Flag meanings: action = callback installed; callback = coordinator alive; coordinatorRequest = recorder active; coordinatorRejected = already stopping; trackingBegin = button enabled; trackingEnd = action fired; deadline = callback installed; captureEnd = error present; writerEnd = writer completed. Recorder rejection means its existing starting/finishing/resource guard rejected the call.

### Usable now, on released v0.2.9

While recording, press **Command-Shift-5 once**, or click the Klik menu-bar icon and select **Record Video (Full Screen)**. Despite its static label, it toggles to Stop when a recording is active, including region recordings. The Region item also uses that active-recording stop path. Confirmed in the `v0.2.9` source tag: AppDelegate menu and Carbon hotkey both reach CaptureCoordinator.toggleVideoRecording, which calls stopVideoRecording when active. This is a verified alternate code route, **not a proven workaround in the failing session**; macOS/another app may own Command-Shift-5 if registration failed, so prefer the menu then. Do not repeatedly toggle after completion (that starts a new recording), and do not force-quit during finalization.

For existing evidence, after stopping safely use **Klik → Export Diagnostics…** in the direct-distribution app. Share the approximate click time/time zone and whether Chrome was fullscreen alongside the export; no need to send the 32-GB movie. The released app lacks the new mouse/action trace, so its export cannot retroactively reconstruct delivery. The export includes other Klik logs, crash reports and system summary: review before sharing. App Store builds do not expose that exporter.

### Diagnostic-build evidence procedure (requires a new build)

This instrumentation is **not installed in the running/released app**. A newly packaged diagnostic app containing this commit must be provided and explicitly authorized before installation/testing. No install, app quit, publishing, or real recording was performed here.

After any current recording has safely finished and the user has voluntarily quit Klik, launch the supplied diagnostic app once with a process-only argument (replace the path with the supplied bundle):

```sh
open "/path/to/Klik.app" --args -KlikStopDiagnostics YES
```

Do not use `open -n` or launch a second instance. The argument will not affect an already-running instance. It writes no persistent defaults; a later ordinary launch disables the trace. For a short blank-window test use a 2-minute auto-stop, try the button before expiry, then the menu fallback if needed. A short passing test does not rule out the reported 90-minute failure. Record the approximate click time and normal/fullscreen context manually; no full-screen capture needs to be shared.

After stop/finalization, export diagnostics. For the narrowest shareable evidence, extract only `KlikStopTrace` lines from the exported `Logs/klik*.log` files and send those plus click time/context. UUID and sequence correlate action to stop phases. Down without action points to hit testing/tracking; action without callback/coordinator isolates delivery/lifetime; accepted coordinator without recorder acceptance isolates scheduling/state; the last begin/end pair identifies the pending shutdown phase. No down at the stated click time remains ambiguous (routing, missing logs, wrong build/flag/session); compare with `sessionStarted` and `barPresented` first.

Regression coverage adds opt-out/no-write and per-session/source/sequence tests; existing native mouse tests now assert down/up, successful action, and drag-out cancellation traces. Tests still bypass WindowServer/Spaces and do not make a live 90-minute recording.


Verification for the opt-in trace: `swift test` passes **23 tests, zero failures**; `swift build -c release` succeeds (existing unrelated warnings). Only the executable was compiled; no signed diagnostic app was packaged or installed. Root cause remains blocked on a trace from an affected physical click.

## Follow-up: confirmed countdown continued (2026-10-02)

**Still unresolved.** The user clarified that the remaining-time counter kept counting **down** after clicking Stop near 90 minutes. This supersedes the ambiguous “advancing” description below. The previous stopping-feedback change is useful but does **not** explain this incident. In the inspected code, an accepted recorder stop cancels the deadline before microphone shutdown, SCStream shutdown, or MP4 finalization. Sustained countdown is therefore evidence against “Stop was accepted but the 32-GB file was just finalizing.” It points earlier in the path, without proving which earlier stage failed.

### Bounded findings

- The recording bar is a borderless **NSWindow**, not an NSPanel and not a nonactivatingPanel. Replacing a supposed nonactivating panel would fix an imaginary implementation. Runtime assertions confirm it cannot become key, its native Stop button accepts first mouse, and the button itself does not move the window on mouse-down. The background is intentionally draggable.
- Window collection flags are canJoinAllSpaces, stationary, fullScreenAuxiliary; level is statusBar; ignoresMouseEvents is false. These are intentions, not proof that WindowServer delivered a physical click while Chrome owned a fullscreen Space. In-process sendEvent tests bypass that routing. No Chrome/fullscreen state was changed in this investigation.
- There are no global/local NSEvent monitors in current Klik source. The bar has no timer-driven window movement or layout constraints that move Stop: Stop is pinned to the trailing edge at a fixed 28×28 points. The ticker only changes label text/accessibility text. Tests confirm unchanged button/window frames across a countdown tick.
- A screenshot region selector or window picker can be invoked while recording and creates mouse-intercepting screenSaver-level windows, above the statusBar-level recording bar. Their normal completion/cancellation orders those windows out before callbacks. The quick-access overlay/toast/HUD are lower, at floating level; the processing HUD also ignores mouse events. This identifies a possible interception route, **not evidence that an overlay was present in the incident**. No speculative z-order or input-policy change was made.
- AppDelegate strongly owns the coordinator, which strongly owns the current bar. The bar's weak-self callback and automatic-stop callback both reach that same coordinator. A permanently lost coordinator would prevent automatic stop too. The coordinator's already-stopping guard is set only after accepting stop; recording stream state and finishing guards do not depend on elapsed minutes or file size. No concrete lifetime/guard defect matching the report was found.
- Relevant local diagnostic search found only launch entries for 0.2.3 on September 16 and no request/accepted/deadline/finalization entries. Those logs cannot diagnose the reported 0.2.9 session. No recording contents or filenames were inspected by the log search.

### New mouse-event tests (not performClick)

RecordingControlBarMouseTests dispatches leftMouseDown through the real NSWindow and supplies leftMouseUp to NSButton's nested AppKit tracking loop. A simulated 90-minute session accepts the click, cancels the actual RecordingStopTimer, and shows Stopping…. A down/drag-out/up sequence cancels the native action, leaves the countdown decreasing, and a subsequent ordinary click works. The latter is expected button behavior and only a controlled symptom reproduction, **not a reproduction or explanation of the user's failure**.

Harness caveat discovered experimentally: prequeuing drag and release can strand AppKit in its tracking loop, while a release outside without a preceding drag can still activate. The retained test delivers drag and release in eventTracking mode; it does not mistake malformed synthetic input for a product bug. The stalled test process was stopped; the running Klik app was not touched.

Verification: full swift test passes **21 tests**, including both mouse tests; release swift build succeeds (existing unrelated warnings remain). Existing build/Klik.app passes codesign --verify --deep --strict and has TeamIdentifier N6P82864Q5. No production source changed in this follow-up, no replacement bundle installed, no recording made, no release/push. Signing validation refers to the existing bundle, not a newly packaged release.

### Next diagnostic boundary and one user question

If a short, authorized reproduction is possible, use a blank test window and a short timer, first normal window then fullscreen Chrome. Do not need a 90-minute or 32-GB capture just to test click routing. Compare floating Stop with the existing Command-Shift-5 recording toggle. Preserve the original recording; do not force-quit during finalization.

Instrumentation plan for a diagnostic build (not added speculatively here): retain existing coordinator/recorder phase logs; add source tags for bar/menu-or-shortcut/automatic stop, bar-window mouse-down hit target and active-Space/visibility/key/app-active booleans, Stop tracking begin/end with action-fired boolean, and callback-presence checks. Use a per-session ID, no window titles, other-app content, global event tap, or screen coordinates. A window event without action isolates tracking; action without accepted coordinator request isolates callback/guard; accepted request without recorder acceptance isolates scheduling/state. No window event cannot alone prove interception without a user-confirmed click and Space context.

**Single highest-value next question:** “When Stop failed, was it the red square on Klik's floating bar over fullscreen Chrome, or were you using the menu/keyboard shortcut?”

## Original investigation: scope and result

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

The counter direction has now been clarified: it continued counting down. See the follow-up above for revised conclusions and the remaining evidence gap. Do not force-quit a potentially finalizing recording or overwrite it.

## UI direction and scoped gate

Reading this as: existing native macOS recording controls for Klik users, preserving native compact style; ENERGY 1 / RHYTHM 1 / MOTION 1 for the changed stopping state.

- PASS, feedback: native label says Stopping… immediately on accepted request; blink ceases and controls disable. No new decoration, colors for branding, assets, navigation, or theme.
- PASS, purpose: existing typography/layout retained for stable controls; neutral indicator distinguishes stopping from live recording without claiming completion.
- PASS, layout/action: regression tests exercise long labels, hit testing and native target/action; no control overlap at supported durations.
- PASS, honesty: no claim of reproduced 90-minute capture fault or completed capture while shutdown is pending.
- PASS, build: direct signed app and Store compilation checked separately; no install or release. Existing full-app accessibility/theme behavior is outside this small state-feedback change, not represented as a new comprehensive audit.
