import XCTest
import AppKit
@testable import Klik

final class ManualRecordingStopTests: XCTestCase {
    @MainActor
    func testQueuedTimeoutCannotStopReplacementSession() async throws {
        var now = 0.0
        var scheduled: [Timer] = []
        let timer = RecordingStopTimer(now: { now }, schedule: { scheduled.append($0) })
        var oldStops = 0
        var newStops = 0
        timer.start(duration: 1) { oldStops += 1 }
        now = 2
        scheduled[0].fire() // Queues the main-actor callback, but cannot run it yet.
        timer.cancel()
        XCTAssertFalse(scheduled[0].isValid)
        timer.start(duration: 1) { newStops += 1 }
        now = 4 // Even with the new deadline elapsed, an old callback must not stop it.
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(oldStops, 0)
        XCTAssertEqual(newStops, 0)
        timer.checkDeadline()
        timer.checkDeadline()
        XCTAssertEqual(newStops, 1)
    }

    @MainActor
    func testStoppingDoesNotResumeDisplayTicker() async throws {
        _ = NSApplication.shared
        let bar = RecordingControlBar()
        bar.remainingTime = { 10 }
        bar.present()
        defer { bar.dismissBar(); bar.onStop = nil }
        let content = try XCTUnwrap(bar.window?.contentView)
        bar.showStopping()
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(content.subviews.compactMap { $0 as? NSTextField }.first?.stringValue, "Stopping…")
    }

    @MainActor
    func testLegacyFinalizationCanKeepClockAdvancingAfterStop() async throws {
        _ = NSApplication.shared
        let timer = RecordingStopTimer()
        timer.start(duration: 600) {}
        let bar = RecordingControlBar()
        bar.remainingTime = { timer.remaining }
        var acceptedStops = 0
        // The old coordinator awaited stopRecording before dismissing the bar.
        // Model that pending finalization without touching capture or user files.
        bar.onStop = { acceptedStops += 1; timer.cancel() }
        bar.present(startedAt: Date().addingTimeInterval(-5400))
        defer { bar.dismissBar() }
        let content = try XCTUnwrap(bar.window?.contentView)
        let stop = try XCTUnwrap(content.subviews.compactMap { $0 as? NSButton }.first {
            $0.action == NSSelectorFromString("stopTapped")
        })
        stop.performClick(nil)
        try await Task.sleep(nanoseconds: 1_150_000_000)
        XCTAssertEqual(acceptedStops, 1)
        XCTAssertNil(timer.remaining)
        XCTAssertEqual(content.subviews.compactMap { $0 as? NSTextField }.first?.stringValue, "90:01")
    }

    @MainActor
    func testNinetyMinuteElapsedAndCountdownLayout() throws {
        _ = NSApplication.shared
        for remaining: Double? in [nil, 1, 600, 5400, 86400] {
            let bar = RecordingControlBar()
            bar.remainingTime = { remaining }
            var stops = 0
            bar.onStop = { stops += 1 }
            bar.present(startedAt: Date().addingTimeInterval(-5400))
            defer { bar.dismissBar() }
            let content = try XCTUnwrap(bar.window?.contentView)
            content.layoutSubtreeIfNeeded()
            let label = try XCTUnwrap(content.subviews.compactMap { $0 as? NSTextField }.first)
            if remaining == nil { XCTAssertEqual(label.stringValue, "90:00") }
            let buttons = content.subviews.compactMap { $0 as? NSButton }
            for button in buttons {
                XCTAssertFalse(label.frame.intersects(button.frame))
                XCTAssertTrue(content.bounds.contains(button.frame))
                XCTAssertTrue(content.hitTest(NSPoint(x: button.frame.midX, y: button.frame.midY)) === button)
            }
            let stop = try XCTUnwrap(buttons.first { $0.action == NSSelectorFromString("stopTapped") })
            stop.performClick(nil)
            XCTAssertEqual(stops, 1)
        }
    }

    @MainActor
    func testRealStopActionBeforeLongDeadlineAndHitTesting() throws {
        _ = NSApplication.shared
        var now = 0.0
        let timer = RecordingStopTimer(now: { now })
        var manualStops = 0
        var automaticStops = 0
        timer.start(duration: 86400) { automaticStops += 1 }
        let bar = RecordingControlBar()
        bar.remainingTime = { timer.remaining }
        bar.onStop = { manualStops += 1; timer.cancel(); bar.showStopping() }
        bar.present()
        defer { bar.dismissBar(); bar.onStop = nil }
        let content = try XCTUnwrap(bar.window?.contentView)
        let stop = try XCTUnwrap(content.subviews.compactMap { $0 as? NSButton }.first {
            $0.action == NSSelectorFromString("stopTapped")
        })
        let label = try XCTUnwrap(content.subviews.compactMap { $0 as? NSTextField }.first)
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(label.stringValue, "1440:00 left")
        XCTAssertFalse(label.frame.intersects(stop.frame))
        XCTAssertTrue(content.hitTest(NSPoint(x: stop.frame.midX, y: stop.frame.midY)) === stop)
        now = 86390
        stop.performClick(nil)
        XCTAssertEqual(manualStops, 1)
        XCTAssertNil(timer.remaining)
        XCTAssertEqual(label.stringValue, "Stopping…")
        XCTAssertTrue(content.subviews.compactMap { $0 as? NSButton }.allSatisfy { !$0.isEnabled })
        stop.performClick(nil)
        XCTAssertEqual(manualStops, 1)
        now = 86401
        timer.checkDeadline()
        XCTAssertEqual(automaticStops, 0)
    }
}
