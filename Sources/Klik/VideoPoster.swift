import AppKit
import AVFoundation

enum VideoPoster {
    static func firstFrame(of url: URL, at seconds: Double = 0.1) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        do {
            let cgImage = try await generator.image(at: time).image
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            NSLog("Klik: poster frame failed — \(error)")
            return nil
        }
    }
}
