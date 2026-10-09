import XCTest
import AppKit
import AVFoundation
import ScreenCaptureKit
@testable import Klik

/// Explicitly consented, bounded real production recorder test. Never enables audio.
final class RecordingVideoNativeTests: XCTestCase {
    @MainActor
    func testColdStartPixelsAndFinalize() async throws {
        guard ProcessInfo.processInfo.environment["KLIK_NATIVE_VIDEO_TEST"] == "1" else {
            throw XCTSkip("Requires explicit screen recording consent and separate synthetic background")
        }
        guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("No existing screen permission") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        XCTAssertTrue(NSApp.windows.isEmpty, "Run this filter alone in a cold process")
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        XCTAssertFalse(content.applications.contains { $0.processID == ProcessInfo.processInfo.processIdentifier })
        let screen = try XCTUnwrap(NSScreen.main)
        let id = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
        let display = try XCTUnwrap(content.displays.first { $0.displayID == id })
        let recorder = VideoRecordingManager()
        let mode = ProcessInfo.processInfo.environment["KLIK_NATIVE_VIDEO_REGION"] == "1"
        for attempt in 0..<2 {
            var bar: RecordingControlBar?
            let region = mode ? CGRect(x: screen.frame.width / 2 - 200, y: 20, width: 400, height: 120) : CGRect(origin: .zero, size: screen.frame.size)
            let url = try await recorder.startRecording(region: region, on: display, screen: screen, captureAudio: false) {
                bar = RecordingControlBar()
                XCTAssertFalse(bar!.window!.isVisible)
            }
            defer { Storage.shared.discardRecording(at: url) }
            let controls = try XCTUnwrap(bar)
            let window = try XCTUnwrap(controls.window)
            controls.present()
            try await Task.sleep(nanoseconds: 1_500_000_000)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(window.alphaValue, 1, accuracy: 0.01)
            XCTAssertFalse(window.ignoresMouseEvents)
            var stopTask: Task<URL, Error>?
            controls.onStop = {
                controls.showStopping()
                stopTask = Task { try await recorder.stopRecording() }
            }
            let view = try XCTUnwrap(window.contentView)
            view.layoutSubtreeIfNeeded()
            let stop = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("stopTapped") })
            let point = stop.convert(NSPoint(x: stop.bounds.midX, y: stop.bounds.midY), to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            }
            NSApp.postEvent(event(.leftMouseUp), atStart: true)
            window.sendEvent(event(.leftMouseDown))
            let task = try XCTUnwrap(stopTask, "Real in-process mouse dispatch must reach Stop")
            let finished = try await task.value
            XCTAssertEqual(finished, url)
            XCTAssertFalse(recorder.isRecording)
            XCTAssertEqual(recorder.microphoneSampleCount, 0)
            controls.onStop = nil
            controls.dismissBar()
            window.orderOut(nil)
            bar = nil
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            XCTAssertGreaterThan(duration, 1)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertTrue(audio.isEmpty, "No system audio or microphone in test artifact")
            let generator = AVAssetImageGenerator(asset: asset)
            let image = try generator.copyCGImage(at: CMTime(seconds: 0.8, preferredTimescale: 600), actualTime: nil)
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let ctx = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            // Entire bar + shadow interior, transformed from AppKit to captured top-left coordinates.
            let top = screen.frame.maxY - window.frame.maxY
            let sx = Double(image.width) / region.width
            let sy = Double(image.height) / region.height
            var checked = 0
            var bad = 0
            for y in stride(from: top + 3, to: top + window.frame.height - 3, by: 3) {
                for x in stride(from: window.frame.minX + 3, to: window.frame.maxX - 3, by: 3) {
                    let px = Int((x - region.minX) * sx)
                    let py = Int((y - region.minY) * sy)
                    guard px >= 0, py >= 0, px < image.width, py < image.height else { continue }
                    let i = (py * image.width + px) * 4
                    checked += 1
                    if !(bytes[i+1] > 190 && bytes[i] > 90 && bytes[i] < 150 && bytes[i+2] > 80 && bytes[i+2] < 145) { bad += 1 }
                }
            }
            print("PIXEL center", Array(bytes[(image.height / 2 * image.width + image.width / 2) * 4 ..< (image.height / 2 * image.width + image.width / 2) * 4 + 4]), "barTop", top)
            XCTAssertGreaterThan(checked, 500)
            XCTAssertEqual(bad, 0, "Underlying green must replace controls, not black or bar pixels")
            print("NATIVE_VIDEO", mode ? "region" : "display", "attempt", attempt, "duration", duration, "checked", checked, "bad", bad, "audioTracks", audio.count, "stop=mouseDispatch")
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}
