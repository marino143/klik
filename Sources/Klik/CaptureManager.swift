import AppKit
import ScreenCaptureKit
import CoreGraphics

enum CaptureError: Error, LocalizedError {
    case noDisplay
    case noContent
    case noPermission
    case captureFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No displays available."
        case .noContent: return "No content available to capture."
        case .noPermission: return "Klik does not have Screen Recording permission. Open System Settings → Privacy & Security → Screen Recording."
        case .captureFailed(let err): return "Capture failed: \(err.localizedDescription)"
        }
    }
}

@MainActor
final class CaptureManager {
    func captureFullDisplay(_ display: SCDisplay, excluding windows: [SCWindow] = []) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: windows)
        let config = makeConfig(width: display.width, height: display.height, sourceRect: nil)
        return try await capture(filter: filter, config: config)
    }

    func captureRegion(_ region: CGRect, on display: SCDisplay, excluding windows: [SCWindow] = []) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: windows)
        let scale = scaleFactor(for: display)
        let config = makeConfig(
            width: Int(region.width * scale),
            height: Int(region.height * scale),
            sourceRect: region
        )
        return try await capture(filter: filter, config: config)
    }

    func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = scaleFactor(for: nil)
        let config = makeConfig(
            width: Int(window.frame.width * scale),
            height: Int(window.frame.height * scale),
            sourceRect: nil
        )
        return try await capture(filter: filter, config: config)
    }

    func shareableContent() async throws -> SCShareableContent {
        if !CGPreflightScreenCaptureAccess() {
            NSLog("Klik: CGPreflightScreenCaptureAccess returned false — requesting access prompt")
            _ = CGRequestScreenCaptureAccess()
            throw CaptureError.noPermission
        }
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch let error as NSError {
            NSLog("Klik: SCShareableContent failed — domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription)")
            if error.code == -3801 || error.code == -3802 {
                throw CaptureError.noPermission
            }
            throw CaptureError.captureFailed(error)
        }
    }

    private func capture(filter: SCContentFilter, config: SCStreamConfiguration) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch let error as NSError {
            NSLog("Klik: captureImage failed — domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription)")
            if error.code == -3801 || error.code == -3802 {
                throw CaptureError.noPermission
            }
            throw CaptureError.captureFailed(error)
        }
    }

    private func makeConfig(width: Int, height: Int, sourceRect: CGRect?) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(width, 1)
        config.height = max(height, 1)
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.displayP3
        if let rect = sourceRect {
            config.sourceRect = rect
        }
        return config
    }

    private func scaleFactor(for display: SCDisplay?) -> CGFloat {
        if let display, let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID }) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }
}
