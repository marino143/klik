import AppKit
import UniformTypeIdentifiers

@MainActor
final class Storage {
    static let shared = Storage()

    private let saveDirectoryPathKey = "Klik.saveDirectory"
    #if APP_STORE
    private let saveDirectoryBookmarkKey = "Klik.saveDirectoryBookmark"
    private var activeSecurityScopedURL: URL?
    #endif

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return f
    }()

    private let filenameLock = NSLock()

    var saveDirectory: URL {
        get {
            #if APP_STORE
            if let url = resolveBookmarkedSaveDirectory() {
                return url
            }
            #else
            if let path = UserDefaults.standard.string(forKey: saveDirectoryPathKey) {
                return URL(fileURLWithPath: path)
            }
            #endif
            return defaultSaveDirectory
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: saveDirectoryPathKey)
            #if APP_STORE
            do {
                let bookmark = try newValue.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmark, forKey: saveDirectoryBookmarkKey)
                activateSecurityScope(for: newValue)
            } catch {
                KlikLog("Klik: failed to store save-folder permission — \(error.localizedDescription)")
            }
            #endif
        }
    }

    var needsSaveDirectorySelection: Bool {
        #if APP_STORE
        return UserDefaults.standard.data(forKey: saveDirectoryBookmarkKey) == nil
        #else
        return false
        #endif
    }

    var defaultSaveDirectory: URL {
        #if APP_STORE
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Klik/Captures", isDirectory: true)
        #else
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        #endif
    }

    @discardableResult
    func chooseSaveDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for Klik captures"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if !needsSaveDirectorySelection {
            panel.directoryURL = saveDirectory
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        saveDirectory = url
        return true
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
            KlikLog("Klik: failed to save image — \(error)")
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

    private var recordingRecoveryDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Klik/Recording Recovery", isDirectory: true)
    }

    /// Recordings live outside /tmp and carry a sidecar until AVAssetWriter has
    /// been finalized. Combined with fragmented MP4 output, this lets the next
    /// launch recover everything through the last completed fragment after a
    /// process crash or force quit.
    func makeTempVideoURL(extension ext: String = "mp4") -> URL {
        let tempDir = recordingRecoveryDirectory
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let filename = "Klik-rec-\(UUID().uuidString.prefix(8)).\(ext)"
        let url = tempDir.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: recoveryMarkerURL(for: url).path, contents: Data())
        return url
    }

    func markRecordingFinished(at url: URL) {
        try? FileManager.default.removeItem(at: recoveryMarkerURL(for: url))
    }

    func discardRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        markRecordingFinished(at: url)
    }

    func recoverableRecordingURLs() -> [URL] {
        let directory = recordingRecoveryDirectory
        guard let markers = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return markers.compactMap { marker in
            guard marker.pathExtension == "recover" else { return nil }
            let video = marker.deletingPathExtension()
            guard FileManager.default.fileExists(atPath: video.path),
                  (try? video.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 else {
                try? FileManager.default.removeItem(at: marker)
                return nil
            }
            return video
        }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
    }

    private func recoveryMarkerURL(for videoURL: URL) -> URL {
        URL(fileURLWithPath: videoURL.path + ".recover")
    }

    @discardableResult
    func moveVideoToFinalLocation(from sourceURL: URL) -> URL? {
        let dir = saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destURL = uniqueURL(in: dir, extension: sourceURL.pathExtension)
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
            markRecordingFinished(at: sourceURL)
            return destURL
        } catch {
            KlikLog("Klik: moveVideoToFinalLocation failed — \(error)")
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

    #if APP_STORE
    private func resolveBookmarkedSaveDirectory() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: saveDirectoryBookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            activateSecurityScope(for: url)
            if isStale {
                let refreshed = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(refreshed, forKey: saveDirectoryBookmarkKey)
            }
            return url
        } catch {
            UserDefaults.standard.removeObject(forKey: saveDirectoryBookmarkKey)
            KlikLog("Klik: save-folder permission expired — \(error.localizedDescription)")
            return nil
        }
    }

    private func activateSecurityScope(for url: URL) {
        if activeSecurityScopedURL?.standardizedFileURL == url.standardizedFileURL { return }
        if let activeSecurityScopedURL {
            activeSecurityScopedURL.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopedURL = url.startAccessingSecurityScopedResource() ? url : nil
    }
    #endif
}
