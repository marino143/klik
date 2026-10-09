import XCTest
@testable import Klik

final class RecordingCaptureExclusionTests: XCTestCase {
    func testUsesProcessIdentityNotBundleOrWindowSnapshot() throws {
        struct App { let pid: Int32; let bundle: String; let windows: [Int] }
        let apps = [App(pid: 12, bundle: "", windows: []),
                    App(pid: 13, bundle: "com.marino.klik", windows: [1])]
        let own = try RecordingCaptureExclusion.ownApplications(
            in: apps, processID: 12, applicationProcessID: { $0.pid })
        XCTAssertEqual(own.map(\.pid), [12])
        // Policy only: this fixture does not establish native application availability.
        XCTAssertTrue(own[0].windows.isEmpty)
    }

    func testMissingProcessFailsInsteadOfCapturingControls() {
        XCTAssertThrowsError(try RecordingCaptureExclusion.ownApplications(
            in: [Int32(13)], processID: 12, applicationProcessID: { $0 }))
    }

    @MainActor
    func testRegistrationRetriesAreBoundedAndFresh() async throws {
        var snapshots = 0
        var pauses = 0
        let own = try await RecordingCaptureExclusion.resolveOwnApplications(
            processID: 12, snapshot: { snapshots += 1; return snapshots == 3 ? [Int32(12)] : [] },
            applicationProcessID: { $0 }, pause: { pauses += 1 })
        XCTAssertEqual(own, [12])
        XCTAssertEqual(snapshots, 3)
        XCTAssertEqual(pauses, 2)
        snapshots = 0; pauses = 0
        do {
            _ = try await RecordingCaptureExclusion.resolveOwnApplications(
                processID: 12, snapshot: { snapshots += 1; return [Int32]() },
                applicationProcessID: { $0 }, pause: { pauses += 1 })
            XCTFail("Must fail closed")
        } catch RecordingCaptureExclusion.Failure.applicationUnavailable {}
        XCTAssertEqual(snapshots, 6)
        XCTAssertEqual(pauses, 5)
        let retry = try await RecordingCaptureExclusion.resolveOwnApplications(
            processID: 12, snapshot: { [Int32(12)] }, applicationProcessID: { $0 })
        XCTAssertEqual(retry, [12])
    }

    @MainActor
    func testEnumerationFailureAndCancellationDoNotFallback() async throws {
        enum Denied: Error { case permission }
        do {
            _ = try await RecordingCaptureExclusion.resolveOwnApplications(
                processID: 12, snapshot: { () -> [Int32] in throw Denied.permission },
                applicationProcessID: { $0 }, pause: { XCTFail("Must not retry API errors") })
            XCTFail("Must propagate API error")
        } catch Denied.permission {}
        do {
            _ = try await RecordingCaptureExclusion.resolveOwnApplications(
                processID: 12, snapshot: { [Int32]() }, applicationProcessID: { $0 },
                pause: { throw CancellationError() })
            XCTFail("Must propagate cancellation")
        } catch is CancellationError {}
    }

    func testWindowExceptionsCannotReincludeOwnControls() {
        let owners: [Int32?] = [12, 13, nil, 12, 14]
        let excluded = RecordingCaptureExclusion.otherWindows(
            in: owners, processID: 12, ownerProcessID: { $0 })
        XCTAssertEqual(excluded, [13, nil, 14])
    }
}
