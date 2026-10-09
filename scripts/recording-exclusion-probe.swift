// Compile with RecordingCaptureExclusion.swift. Enumerates only; never captures pixels/audio.
import AppKit
import ScreenCaptureKit

@main struct RecordingExclusionProbe {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        guard CGPreflightScreenCaptureAccess() else {
            print("BLOCKED: screen capture consent unavailable; no permission requested")
            exit(2)
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let cold = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard cold.applications.allSatisfy({ $0.processID != pid }) else {
            fatalError("Not a cold menu-only process")
        }
        do {
            _ = try RecordingCaptureExclusion.ownApplications(in: cold.applications, processID: pid, applicationProcessID: { $0.processID })
            fatalError("Old guard unexpectedly succeeded")
        } catch RecordingCaptureExclusion.Failure.applicationUnavailable {
            print("PASS reproduced cold-start regression: own process absent")
        }
        for attempt in 1...3 {
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 320, height: 38),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .statusBar
            _ = window.windowNumber
            let apps = try await RecordingCaptureExclusion.resolveOwnApplications()
            precondition(apps.count == 1 && apps[0].processID == pid)
            precondition(!window.isVisible)
            print("PASS attempt \(attempt): materialized, never-presented control resolves owner")
            window.close()
        }
    }
}
