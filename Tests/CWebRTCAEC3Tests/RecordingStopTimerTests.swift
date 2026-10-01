import XCTest
import AppKit
@testable import Klik

final class RecordingStopTimerTests: XCTestCase {
    func testValidationAndPersistence() {
        XCTAssertEqual(RecordingStopSettings.duration(minutes: "0", seconds: "1"), 1)
        XCTAssertEqual(RecordingStopSettings.duration(minutes: " 12 ", seconds: "30"), 750)
        XCTAssertEqual(RecordingStopSettings.duration(minutes: "1440", seconds: "0"), 86400)
        for (minutes, seconds) in [("0", "0"), ("-1", "0"), ("1.5", "0"), ("", "0"), ("abc", "2"), ("1", "60"), ("1440", "1"), ("99999999999999999999999", "0")] {
            XCTAssertNil(RecordingStopSettings.duration(minutes: minutes, seconds: seconds))
        }
        let name = "KlikStopTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = RecordingStopSettings(defaults: defaults)
        XCTAssertFalse(settings.enabled)
        XCTAssertNil(settings.duration)
        settings.enabled = true
        settings.seconds = 75
        settings.save(defaults: defaults)
        XCTAssertEqual(RecordingStopSettings(defaults: defaults).duration, 75)
        settings.enabled = false
        settings.save(defaults: defaults)
        XCTAssertNil(RecordingStopSettings(defaults: defaults).duration)
        XCTAssertEqual(RecordingStopSettings(defaults: defaults).seconds, 75)
        for invalid in [-1, 0, 86401] {
            defaults.set(invalid, forKey: "recordingStopSeconds")
            defaults.set(true, forKey: "recordingStopEnabled")
            XCTAssertNil(RecordingStopSettings(defaults: defaults).duration)
        }
    }

    @MainActor
    func testTimeoutOnceAndElapsedTimeSemantics() {
        var time = 100.0
        let timer = RecordingStopTimer(now: { time })
        var stops = 0
        timer.start(duration: 60) { stops += 1; timer.checkDeadline() }
        time = 130
        XCTAssertEqual(timer.remaining, 30)
        timer.checkDeadline()
        XCTAssertEqual(stops, 0)
        // No pause API exists. Idle UI time / microphone mute still count.
        time = 160
        timer.checkDeadline()
        timer.checkDeadline()
        XCTAssertEqual(stops, 1)
        XCTAssertNil(timer.remaining)
    }

    @MainActor
    func testCancellationReplacementAndDisabledTimer() {
        var time = 0.0
        let timer = RecordingStopTimer(now: { time })
        var stops = 0
        timer.start(duration: 1) { stops += 100 }
        timer.cancel()
        time = 2
        timer.checkDeadline()
        XCTAssertEqual(stops, 0)
        timer.start(duration: 1) { stops += 100 }
        timer.start(duration: 10) { stops += 1 }
        time = 4
        timer.checkDeadline()
        XCTAssertEqual(stops, 0)
        time = 12
        timer.checkDeadline()
        XCTAssertEqual(stops, 1)
        for duration: Double? in [nil, 0, -1, .infinity, .nan] {
            timer.start(duration: duration) { stops += 100 }
            timer.checkDeadline()
            XCTAssertNil(timer.remaining)
        }
        XCTAssertEqual(stops, 1)
    }

    @MainActor
    func testFoundationTimerActuallyFiresOnce() async {
        let timer = RecordingStopTimer()
        let fired = expectation(description: "timeout")
        fired.assertForOverFulfill = true
        timer.start(duration: 0.01) { fired.fulfill() }
        await fulfillment(of: [fired], timeout: 2)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(timer.remaining)
    }

    @MainActor
    func testSettingsControlsAndCountdown() throws {
        _ = NSApplication.shared
        let keys = ["recordingStopEnabled", "recordingStopSeconds"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            SettingsWindowController.shared.close()
        }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        SettingsWindowController.shared.show()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let content = try XCTUnwrap(SettingsWindowController.shared.window?.contentView)
        let views = descendants(content)
        let checkbox = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "Automatically stop recording" })
        let fields = views.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(checkbox.state, .off)
        XCTAssertTrue(fields.allSatisfy { !$0.isEnabled })
        checkbox.performClick(nil)
        XCTAssertTrue(fields.allSatisfy { $0.isEnabled })
        fields[0].stringValue = "1"
        fields[1].stringValue = "15"
        SettingsWindowController.shared.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: fields[1]))
        XCTAssertEqual(RecordingStopSettings().duration, 75)
        fields[1].stringValue = "60"
        SettingsWindowController.shared.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: fields[1]))
        XCTAssertNil(RecordingStopSettings().duration)
        XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Timer is off.") })
        fields[1].stringValue = "0"
        SettingsWindowController.shared.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: fields[1]))
        XCTAssertEqual(RecordingStopSettings().duration, 60)
        checkbox.performClick(nil)
        XCTAssertNil(RecordingStopSettings().duration)
        let bar = RecordingControlBar()
        bar.remainingTime = { 86400 }
        var stops = 0
        bar.onStop = { stops += 1 }
        bar.present()
        defer { bar.dismissBar() }
        let barViews = descendants(try XCTUnwrap(bar.window?.contentView))
        XCTAssertTrue(barViews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "1440:00 left" })
        let stop = try XCTUnwrap(barViews.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("stopTapped") })
        stop.performClick(nil)
        XCTAssertEqual(stops, 1)
    }
}
