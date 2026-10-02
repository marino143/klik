import XCTest
import AppKit
@testable import Klik

final class RecordingStopDiagnosticsTests: XCTestCase {
    @MainActor
    func testDisabledTraceDoesNotWrite() {
        var lines: [String] = []
        let trace = RecordingStopDiagnostics(enabled: false, sink: { lines.append($0) })
        trace.event(.sessionStarted)
        trace.event(.action, source: .bar, flag: true)
        XCTAssertTrue(lines.isEmpty)
    }

    @MainActor
    func testSessionIdentitySequenceAndSource() {
        var lines: [String] = []
        let trace = RecordingStopDiagnostics(enabled: true, sink: { lines.append($0) })
        trace.event(.sessionStarted)
        trace.event(.coordinatorRejected, source: .menuOrShortcut, flag: true)
        trace.event(.deadline, source: .automatic)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("session=\(trace.id) seq=1"))
        XCTAssertTrue(lines[1].contains("phase=coordinatorRejected source=menuOrShortcut flag=true"))
        XCTAssertTrue(lines[2].contains("seq=3"))
        XCTAssertTrue(lines[2].contains("phase=deadline source=automatic"))
        XCTAssertNotEqual(trace.id, RecordingStopDiagnostics(enabled: false).id)
    }
}
