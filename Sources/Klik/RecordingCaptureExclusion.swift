import Foundation

enum RecordingCaptureExclusion {
    enum Failure: Error, LocalizedError {
        case applicationUnavailable

        var errorDescription: String? {
            "Recording could not start because Klik could not exclude its controls from capture. Please try again."
        }
    }

    static func ownApplications<Application>(
        in applications: [Application], processID: Int32,
        applicationProcessID: (Application) -> Int32
    ) throws -> [Application] {
        let own = applications.filter { applicationProcessID($0) == processID }
        guard !own.isEmpty else { throw Failure.applicationUnavailable }
        return own
    }

    // Exceptions owned by an excluded app are INCLUDED by ScreenCaptureKit.
    // Only other apps' windows may be additional exclusions.
    static func otherWindows<Window>(
        in windows: [Window], processID: Int32, ownerProcessID: (Window) -> Int32?
    ) -> [Window] {
        windows.filter { ownerProcessID($0) != processID }
    }
}
