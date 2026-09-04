import AppKit
import UniformTypeIdentifiers

@MainActor
final class Storage {
    static let shared = Storage()

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return f
    }()

    private let filenameLock = NSLock()

    var saveDirectory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: "Klik.saveDirectory") {
                return URL(fileURLWithPath: path)
            }
            return defaultSaveDirectory
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: "Klik.saveDirectory")
        }
    }

    var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var copyToClipboardOnCapture: Bool {
        get { UserDefaults.standard.object(forKey: "Klik.copyOnCapture") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "Klik.copyOnCapture") }
    }

    var autoSaveOnCapture: Bool {
        get { UserDefaults.standard.object(forKey: "Klik.autoSaveOnCapture") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "Klik.autoSaveOnCapture") }
    }

    /// PNG bytes straight from the CGImage through ImageIO. The previous
    /// route (`tiffRepresentation` → `NSBitmapImageRep` → PNG) materialised
    /// two extra ~60 MB buffers for every 5K capture.
    static func pngData(_ cg: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    @discardableResult
    func savePNG(_ png: Data, to directory: URL? = nil) -> URL? {
        let dir = directory ?? saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = uniqueURL(in: dir, extension: "png")
        do {
            try png.write(to: url)
            return url
        } catch {
            NSLog("Klik: failed to save image — \(error)")
            return nil
        }
    }

    @discardableResult
    func saveImage(_ image: NSImage, to directory: URL? = nil) -> URL? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = Self.pngData(cg) else { return nil }
        return savePNG(png, to: directory)
    }

    /// PNG only — every app that takes an image paste reads public.png, and
    /// the TIFF that `writeObjects([NSImage])` adds is another full-size copy.
    func copyToClipboard(png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    func copyToClipboard(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = Self.pngData(cg) else { return }
        copyToClipboard(png: png)
    }

    func makeVideoURL(extension ext: String = "mp4") -> URL {
        let dir = saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return uniqueURL(in: dir, extension: ext)
    }

    func makeTempVideoURL(extension ext: String = "mp4") -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Klik", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let filename = "Klik-rec-\(UUID().uuidString.prefix(8)).\(ext)"
        return tempDir.appendingPathComponent(filename)
    }

    @discardableResult
    func moveVideoToFinalLocation(from sourceURL: URL) -> URL? {
        let dir = saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destURL = uniqueURL(in: dir, extension: sourceURL.pathExtension)
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
            return destURL
        } catch {
            NSLog("Klik: moveVideoToFinalLocation failed — \(error)")
            return nil
        }
    }


    private func uniqueURL(in directory: URL, extension ext: String) -> URL {
        filenameLock.lock()
        defer { filenameLock.unlock() }

        let base = "Klik \(formatter.string(from: Date()))"
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base) \(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }
}
