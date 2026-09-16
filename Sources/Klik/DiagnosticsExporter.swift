import AppKit

@MainActor
enum DiagnosticsExporter {
    static func export() {
        let panel = NSSavePanel()
        panel.title = "Export Klik Diagnostics"
        panel.nameFieldStringValue = "Klik Diagnostics \(filenameTimestamp()).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        DiagnosticsLogger.shared.flush()

        Task {
            do {
                try await createArchive(at: destination)
                NotificationToast.show(message: "Diagnostics exported")
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                KlikLog("Klik: diagnostics export failed: \(error)")
                let alert = NSAlert()
                alert.messageText = "Diagnostics export failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private static func createArchive(at destination: URL) async throws {
        try await Task.detached {
            let fileManager = FileManager.default
            let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("Klik-Diagnostics-\(UUID().uuidString)", isDirectory: true)
            let bundle = tempRoot.appendingPathComponent("Klik Diagnostics", isDirectory: true)
            defer { try? fileManager.removeItem(at: tempRoot) }

            try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)
            try copyLogs(to: bundle, fileManager: fileManager)
            try copyCrashReports(to: bundle, fileManager: fileManager)
            try systemSummary().write(
                to: bundle.appendingPathComponent("system.txt"),
                atomically: true,
                encoding: .utf8
            )

            try? fileManager.removeItem(at: destination)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", bundle.path, destination.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
        }.value
    }

    nonisolated private static func copyLogs(to destination: URL, fileManager: FileManager) throws {
        let source = DiagnosticsLogger.shared.logsDirectory
        guard let files = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        let logsDestination = destination.appendingPathComponent("Logs", isDirectory: true)
        try fileManager.createDirectory(at: logsDestination, withIntermediateDirectories: true)
        for file in files where file.pathExtension == "log" {
            try? fileManager.copyItem(at: file, to: logsDestination.appendingPathComponent(file.lastPathComponent))
        }
    }

    nonisolated private static func copyCrashReports(to destination: URL, fileManager: FileManager) throws {
        let reportsDirectory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let reports = try? fileManager.contentsOfDirectory(
            at: reportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let matching = reports.filter { report in
            let name = report.lastPathComponent.lowercased()
            let date = (try? report.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return name.hasPrefix("klik-") && ["ips", "crash"].contains(report.pathExtension.lowercased()) && date >= cutoff
        }
        guard !matching.isEmpty else { return }

        let crashDestination = destination.appendingPathComponent("Crash Reports", isDirectory: true)
        try fileManager.createDirectory(at: crashDestination, withIntermediateDirectories: true)
        for report in matching.suffix(10) {
            try? fileManager.copyItem(at: report, to: crashDestination.appendingPathComponent(report.lastPathComponent))
        }
    }

    nonisolated private static func systemSummary() -> String {
        let info = ProcessInfo.processInfo
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "unknown"
        #endif
        return """
        Klik version: \(shortVersion) (\(build))
        macOS: \(info.operatingSystemVersionString)
        Architecture: \(architecture)
        Generated: \(ISO8601DateFormatter().string(from: Date()))

        This archive contains local Klik logs and up to 10 Klik crash reports from the last 30 days.
        It does not include recordings, screenshots, clipboard contents, or files from the save directory.
        """
    }

    private static func filenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}
