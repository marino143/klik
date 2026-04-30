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
}
