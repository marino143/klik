import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum GIFConverterError: Error, LocalizedError {
    case noVideoTrack
    case destinationFailed
    case generationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:           return "Video has no video track."
        case .destinationFailed:      return "Cannot create GIF destination."
        case .generationFailed(let e):return "Frame generation failed: \(e.localizedDescription)"
        }
    }
}

enum GIFConverter {
    static func convert(
        videoURL: URL,
        outputURL: URL,
        frameRate: Double = 12,
        maxWidth: CGFloat = 720
    ) async throws {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = duration.seconds
        guard totalSeconds > 0 else { throw GIFConverterError.noVideoTrack }

        let frameCount = max(2, Int(totalSeconds * frameRate))
        let interval = totalSeconds / Double(frameCount)
        let times: [CMTime] = (0..<frameCount).map {
            CMTime(seconds: Double($0) * interval, preferredTimescale: 600)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let scale = min(1.0, maxWidth / naturalSize.width)
            generator.maximumSize = CGSize(
                width: naturalSize.width * scale,
                height: naturalSize.height * scale
            )
        }

        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else { throw GIFConverterError.destinationFailed }

        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: 1.0 / frameRate,
                kCGImagePropertyGIFUnclampedDelayTime as String: 1.0 / frameRate,
            ]
        ]
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)

        for time in times {
            do {
                let cgImage = try await generator.image(at: time).image
                CGImageDestinationAddImage(dest, cgImage, frameProperties as CFDictionary)
            } catch {
                throw GIFConverterError.generationFailed(error)
            }
        }

        if !CGImageDestinationFinalize(dest) {
            throw GIFConverterError.destinationFailed
        }
    }
}
