# Idle memory investigation — 2026-10-02

Report: about 430 MB in Activity Monitor while Klik is idle in the menu bar.
This number alone does not demonstrate a leak. Fresh-launch idle and idle after
recording/editing must be distinguished. No link to the unresolved Stop report
has been established.

## Observed, not inferred

- Source inspected at fb73b5b (public release is 0.2.9, plus local Stop diagnostics).
- Existing local /Applications/Klik.app is **0.2.0**, not the reported release.
  A read-only vmmap -summary of PID 65525 reported physical footprint 21.8 MB,
  peak 115.0 MB. This neither reproduces nor disproves the user's 430 MB.
  RSS is not the Activity Monitor Memory/physical-footprint metric; virtual
  address space and total mapped resident pages are not that metric either.
- No recording, microphone capture, user-media access, app installation,
  restart or quitting of the running app was performed.

## Ownership review

- Recorder stop/cancel/unexpected-stop paths finish the writer then clear
  stream, stream output, writer, writer inputs, microphone engine and timestamps.
  Microphone tap is removed and engine stopped. Stream output owns the recorder
  weakly. An unresolved framework stop/finalize await can retain live resources
  until it returns, but this was **not** reproduced or attributed to this report.
- The application has no AVPlayer or playback time-observer implementation;
  opening a recording delegates to NSWorkspace. Posters are capped at 640 pixels.
- Screenshot overlays hold downscaled thumbnails and file URLs; editors/pins
  intentionally hold full images while open. Controller registries remove
  closed windows; their action closures capture controllers weakly.
- Overlay stacks are not capped. Undismissed overlays remain owned, including
  those stacked above the visible screen. This is a possible workload-dependent
  contributor, not evidence of a closed-window leak or this report's cause.
- Editor Core Image context is per canvas. Synthetic closed-editor tests release
  both canvas and image. Framework/allocator caches may not return footprint to
  the launch baseline immediately; weak-reference tests do not measure those.
- Offline echo mixing materializes entire audio tracks in local Float arrays.
  One mono 48 kHz Float array is 192,000 bytes/second (~691 MB/hour), and multiple
  arrays may coexist during processing. This is a real processing-memory scaling
  limitation, **not evidence of retained arrays after completed processing**.
  Writer readiness callbacks merit instrumented follow-up if post-processing
  growth is reproducible. No speculative pipeline rewrite was made.

## Bounded regression coverage

IdleResourceLifetimeTests uses synthetic objects, no capture or playback:

- 20 editor create/close cycles: weak controller, canvas and image must clear.
- 20 video-overlay create/close cycles: weak controller, state and poster clear.
- 100 idle recorder/coordinator lifecycles: weak instances clear.
- 100 timer start/cancel cycles: callback-owned payload clears on cancellation.

These check direct controller closure and ARC ownership, not visible-window
registry insertion, real SCStream teardown, long recordings or process footprint.
All four passed. The full direct-variant Swift test suite also passed: 27 tests,
zero failures, including existing synthetic audio-mixing tests. No evidenced
production leak was found, so no speculative production-memory fix is included.

Direct build (explicitly unset App Store variant):

    env -u KLIK_APP_STORE bash build.sh release
    codesign --verify --deep --strict --verbose=2 build/Klik.app
    codesign -dv --verbose=2 build/Klik.app

Build and signature verification passed with the Apple Development identity;
this is a local development-signed build, not a notarized/public release.

## Next discriminator

Ask only: **Is the 430 MB present immediately after a fresh launch before any
capture, or only after recording/editing?** No need to send screenshots or media.
For a follow-up, compare the same build and same physical-footprint metric at
fresh idle, after processing completes, and after previews/editors/pins close.
Repeated monotonic growth across the same bounded workload is more informative
than one reading. Do not treat the older local app as the user's baseline.
