import Foundation
@preconcurrency import ScreenCaptureKit

enum RecordingCaptureExclusion {
    enum Failure: Error, LocalizedError {
        case applicationUnavailable

        var errorDescription: String? {
            "Recording could not start because Klik could not exclude its controls from capture. Please try again."
        }
    }

    @MainActor
    static func resolveOwnApplications() async throws -> [SCRunningApplication] {
        try await resolveOwnApplications(
            processID: ProcessInfo.processInfo.processIdentifier,
            snapshot: {
                try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false).applications
            }, applicationProcessID: { $0.processID })
    }

    @MainActor
    static func resolveOwnApplications<Application>(
        processID: Int32,
        snapshot: () async throws -> [Application],
        applicationProcessID: (Application) -> Int32,
        pause: () async throws -> Void = { try await Task.sleep(nanoseconds: 50_000_000) }
    ) async throws -> [Application] {
        for attempt in 0..<6 {
            try Task.checkCancellation()
            let applications = try await snapshot()
            if let own = try? ownApplications(in: applications, processID: processID,
                                              applicationProcessID: applicationProcessID) {
                return own
            }
            if attempt < 5 { try await pause() }
        }
        throw Failure.applicationUnavailable
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
