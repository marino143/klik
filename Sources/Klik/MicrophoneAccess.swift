import AppKit
import AVFoundation

@MainActor
enum MicrophoneAccess {
    static var currentStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var isGranted: Bool {
        currentStatus == .authorized
    }

    /// Returns true if permission is (or becomes) granted. Triggers the system
    /// prompt only when status is `.notDetermined`.
    static func request() async -> Bool {
        switch currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
