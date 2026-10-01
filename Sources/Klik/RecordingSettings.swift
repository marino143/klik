import Foundation

struct RecordingSettings {
    enum Resolution: Int, CaseIterable {
        case p720 = 720, p1080 = 1080, p1440 = 1440, native = 0
        var title: String { self == .native ? "Original (Retina)" : "\(rawValue)p" }
    }
    enum Quality: String, CaseIterable {
        case small, standard, high
        var title: String {
            switch self {
            case .small: return "Smaller file"
            case .standard: return "Standard"
            case .high: return "High"
            }
        }
        var multiplier: Double {
            switch self { case .small: return 0.75; case .standard: return 1.5; case .high: return 4.0 }
        }
        var cap: Int {
            switch self { case .small: return 3_000_000; case .standard: return 6_000_000; case .high: return 40_000_000 }
        }
    }
    var resolution: Resolution = .p1080
    var fps: Int = 30
    var quality: Quality = .standard

    init(defaults: UserDefaults = .standard) {
        resolution = Resolution(rawValue: defaults.object(forKey: "recordingResolution") as? Int ?? 1080) ?? .p1080
        fps = defaults.integer(forKey: "recordingFPS") == 60 ? 60 : 30
        quality = Quality(rawValue: defaults.string(forKey: "recordingQuality") ?? "standard") ?? .standard
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(resolution.rawValue, forKey: "recordingResolution")
        defaults.set(fps, forKey: "recordingFPS")
        defaults.set(quality.rawValue, forKey: "recordingQuality")
    }

    func dimensions(width: Int, height: Int) -> (width: Int, height: Int) {
        let cap = resolution.rawValue
        let scale = cap > 0 && height > cap ? Double(cap) / Double(height) : 1.0
        return (max(2, Int(Double(width) * scale) & ~1), max(2, Int(Double(height) * scale) & ~1))
    }

    func bitrate(width: Int, height: Int) -> Int {
        let frameScale = Double(fps) / 30.0
        return min(Int(Double(width) * Double(height) * quality.multiplier * frameScale), Int(Double(quality.cap) * frameScale))
    }
}
