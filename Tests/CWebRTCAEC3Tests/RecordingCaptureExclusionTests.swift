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
        // No visible controls required at snapshot time; the filter selects an app.
        XCTAssertTrue(own[0].windows.isEmpty)
    }

    func testMissingProcessFailsInsteadOfCapturingControls() {
        XCTAssertThrowsError(try RecordingCaptureExclusion.ownApplications(
            in: [Int32(13)], processID: 12, applicationProcessID: { $0 }))
    }

    func testWindowExceptionsCannotReincludeOwnControls() {
        let owners: [Int32?] = [12, 13, nil, 12, 14]
        let excluded = RecordingCaptureExclusion.otherWindows(
            in: owners, processID: 12, ownerProcessID: { $0 })
        XCTAssertEqual(excluded, [13, nil, 14])
    }
}
