import AppKit

final class VideoMediaState {
    var fileURL: URL
    var isPendingSave: Bool
    let poster: NSImage

    init(fileURL: URL, poster: NSImage, isPendingSave: Bool) {
        self.fileURL = fileURL
        self.poster = poster
        self.isPendingSave = isPendingSave
    }
}

enum Media {
    /// The NSImage is a small thumbnail — the full capture lives on disk at
    /// `fileURL`. Keeping the 5K bitmap alive per overlay cost ~60 MB each,
    /// and overlays stack until dismissed.
    case image(NSImage, fileURL: URL)
    case video(VideoMediaState)

    var fileURL: URL {
        switch self {
        case .image(_, let url): return url
        case .video(let state): return state.fileURL
        }
    }

    var displayImage: NSImage {
        switch self {
        case .image(let img, _):  return img
        case .video(let state):   return state.poster
        }
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }

    /// Full-resolution image for the editor / clipboard, re-read from disk.
    /// Falls back to the thumbnail if the file has been moved meanwhile.
    func loadFullImage() -> NSImage {
        switch self {
        case .image(let thumb, let url): return NSImage(contentsOf: url) ?? thumb
        case .video(let state):          return state.poster
        }
    }
}

extension NSImage {
    /// A genuinely downscaled bitmap (not an NSImage with a smaller `size`
    /// still wrapping the full rep), so the source pixels can be released.
    static func thumbnail(of cg: CGImage, maxPixelSize: CGFloat) -> NSImage {
        let full = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let scale = min(1, maxPixelSize / CGFloat(max(cg.width, cg.height)))
        guard scale < 1 else { return full }
        let w = max(1, Int(CGFloat(cg.width) * scale))
        let h = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return full }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let small = ctx.makeImage() else { return full }
        return NSImage(cgImage: small, size: NSSize(width: w, height: h))
    }
}
