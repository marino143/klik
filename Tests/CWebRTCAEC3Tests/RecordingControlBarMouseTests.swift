import XCTest
import AppKit
@testable import Klik

/// In-process AppKit dispatch, deliberately not performClick. This exercises
/// hit testing and NSButton's tracking loop, but not WindowServer/Spaces routing.
final class RecordingControlBarMouseTests: XCTestCase {
    @MainActor
    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
    }

    @MainActor
    private func click(_ button: NSButton, in window: NSWindow, releaseOutside: Bool = false) throws {
        let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let release = releaseOutside ? NSPoint(x: 2, y: 2) : center
        // NSButton.mouseDown consumes release in a nested tracking loop.
        // For dragging, deliver events in tracking mode instead of prequeuing
        // both: AppKit may discard a prequeued release when starting tracking.
        // All events stay inside this test process.
        let up = try mouse(.leftMouseUp, at: release, in: window)
        if releaseOutside {
            let drag = try mouse(.leftMouseDragged, at: release, in: window)
            let sendDrag: @MainActor @Sendable () -> Void = { NSApp.postEvent(drag, atStart: true) }
            let sendUp: @MainActor @Sendable () -> Void = { NSApp.postEvent(up, atStart: true) }
            let dragTimer = Timer(timeInterval: 0.02, repeats: false) { _ in
                MainActor.assumeIsolated { sendDrag() }
            }
            let upTimer = Timer(timeInterval: 0.05, repeats: true) { _ in
                MainActor.assumeIsolated { sendUp() }
            }
            RunLoop.main.add(dragTimer, forMode: .eventTracking)
            RunLoop.main.add(upTimer, forMode: .eventTracking)
            defer { dragTimer.invalidate(); upTimer.invalidate() }
            window.sendEvent(try mouse(.leftMouseDown, at: center, in: window))
            return
        }
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(try mouse(.leftMouseDown, at: center, in: window))
    }

    @MainActor
    func testMouseDispatchStopsBeforeDeadlineAtNinetyMinutes() throws {
        _ = NSApplication.shared
        var now = 0.0
        let timer = RecordingStopTimer(now: { now })
        timer.start(duration: 7200) {}
        now = 5400
        let bar = RecordingControlBar()
        bar.remainingTime = { timer.remaining }
        var stops = 0
        bar.onStop = { stops += 1; timer.cancel(); bar.showStopping() }
        bar.present(startedAt: Date().addingTimeInterval(-5400))
        defer { bar.window?.orderOut(nil); bar.dismissBar(); bar.onStop = nil }
        let window = try XCTUnwrap(bar.window)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let stop = try XCTUnwrap(content.subviews.compactMap { $0 as? NSButton }.first {
            $0.action == NSSelectorFromString("stopTapped")
        })
        XCTAssertFalse(window is NSPanel)
        XCTAssertFalse(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertTrue(stop.acceptsFirstMouse(for: nil))
        XCTAssertFalse(stop.mouseDownCanMoveWindow)
        try click(stop, in: window)
        XCTAssertEqual(stops, 1)
        XCTAssertNil(timer.remaining)
        XCTAssertEqual(content.subviews.compactMap { $0 as? NSTextField }.first?.stringValue, "Stopping…")
    }

    @MainActor
    func testReleaseOutsideCancelsClickAndCountdownContinues() async throws {
        _ = NSApplication.shared
        var now = 5400.0
        let timer = RecordingStopTimer(now: { now })
        timer.start(duration: 600) {}
        let bar = RecordingControlBar()
        bar.remainingTime = { timer.remaining }
        var stops = 0
        bar.onStop = { stops += 1; timer.cancel(); bar.showStopping() }
        bar.present(startedAt: Date().addingTimeInterval(-5400))
        defer { bar.window?.orderOut(nil); bar.dismissBar(); bar.onStop = nil }
        let window = try XCTUnwrap(bar.window)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let stop = try XCTUnwrap(content.subviews.compactMap { $0 as? NSButton }.first {
            $0.action == NSSelectorFromString("stopTapped")
        })
        let originalFrame = stop.frame
        let originalWindowFrame = window.frame
        try click(stop, in: window, releaseOutside: true)
        XCTAssertEqual(stops, 0)
        now += 1
        try await Task.sleep(nanoseconds: 650_000_000)
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(content.subviews.compactMap { $0 as? NSTextField }.first?.stringValue, "09:59 left")
        XCTAssertEqual(stop.frame, originalFrame)
        XCTAssertEqual(window.frame, originalWindowFrame)
        try click(stop, in: window)
        XCTAssertEqual(stops, 1)
        XCTAssertNil(timer.remaining)
    }
}
