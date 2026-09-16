import Foundation

func KlikLog(_ message: @autoclosure () -> String) {
    let value = DiagnosticsLogger.sanitize(message())
    NSLog("%@", value)
    DiagnosticsLogger.shared.write(value)
}

final class DiagnosticsLogger: @unchecked Sendable {
    static let shared = DiagnosticsLogger()

    private let queue = DispatchQueue(label: "com.marino.klik.diagnostics")
    private let maxFileSize: UInt64 = 1_000_000
    private let retainedFiles = 5
    private var handle: FileHandle?

    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var logsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Klik/Logs", isDirectory: true)
    }

    private var currentLogURL: URL {
        logsDirectory.appendingPathComponent("klik.log")
    }

    func start() {
        queue.sync {
            openLogIfNeeded()
            writeUnlocked("Klik launched, version \(Self.appVersion)")
        }
    }

    func write(_ message: String) {
        queue.async { [self] in
            openLogIfNeeded()
            rotateIfNeeded(addingBytes: message.utf8.count + 40)
            writeUnlocked(message)
        }
    }

    func flush() {
        queue.sync {
            try? handle?.synchronize()
        }
    }

    static func sanitize(_ message: String) -> String {
        message
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func openLogIfNeeded() {
        guard handle == nil else { return }
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: currentLogURL.path) {
            FileManager.default.createFile(atPath: currentLogURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: currentLogURL)
        _ = try? handle?.seekToEnd()
    }

    private func writeUnlocked(_ message: String) {
        let line = "\(timestampFormatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        try? handle?.write(contentsOf: data)
        try? handle?.synchronize()
    }

    private func rotateIfNeeded(addingBytes: Int) {
        let currentSize = (try? currentLogURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard currentSize + addingBytes > maxFileSize else { return }

        try? handle?.close()
        handle = nil
        for index in stride(from: retainedFiles - 1, through: 1, by: -1) {
            let source = logsDirectory.appendingPathComponent("klik.\(index).log")
            let destination = logsDirectory.appendingPathComponent("klik.\(index + 1).log")
            try? FileManager.default.removeItem(at: destination)
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.moveItem(at: source, to: destination)
            }
        }
        let firstArchive = logsDirectory.appendingPathComponent("klik.1.log")
        try? FileManager.default.removeItem(at: firstArchive)
        try? FileManager.default.moveItem(at: currentLogURL, to: firstArchive)
        openLogIfNeeded()
    }

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(short) (\(build))"
    }
}
