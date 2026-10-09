import XCTest
import AppKit
import ScreenCaptureKit
@testable import Klik

final class RecordingCaptureNativeTests: XCTestCase {
    @MainActor
    func testRealControlWindowRegistersWithoutPresentationAndReleases() async throws {
        guard ProcessInfo.processInfo.environment["KLIK_NATIVE_EXCLUSION_TEST"] == "1" else {
            throw XCTSkip("Opt-in native enumeration; no pixels/audio captured")
        }
        guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("Screen capture permission unavailable") }
        _ = NSApplication.shared
        for _ in 0..<3 {
            var bar: RecordingControlBar? = RecordingControlBar()
            weak var releasedBar = bar
            let window = try XCTUnwrap(bar?.window)
            XCTAssertFalse(window.isVisible)
            _ = window.windowNumber
            let applications = try await RecordingCaptureExclusion.resolveOwnApplications()
            XCTAssertTrue(applications.contains { $0.processID == ProcessInfo.processInfo.processIdentifier })
            XCTAssertFalse(window.isVisible)
            bar?.dismissBar()
            bar = nil
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertNil(releasedBar)
            XCTAssertFalse(window.isVisible)
        }
    }
}
