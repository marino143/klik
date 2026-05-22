import AppKit
import ScreenCaptureKit

@MainActor
final class CaptureCoordinator {
    private let manager = CaptureManager()
    private let recorder = VideoRecordingManager()
    private var regionSelector: RegionSelectorController?
    private var windowPicker: WindowPickerController?
    private var recordingControlBar: RecordingControlBar?

    var isRecording: Bool { recorder.isRecording }

    func captureFullScreen() {
        Task {
            do {
                let content = try await manager.shareableContent()
                guard let display = content.displays.first else {
                    showError(CaptureError.noDisplay)
                    return
                }
                let image = try await manager.captureFullDisplay(display)
                handleCapturedImage(image)
            } catch {
                showError(error)
            }
        }
    }

    func captureRegion() {
        Task {
            do {
                let content = try await manager.shareableContent()
                let selector = RegionSelectorController()
                self.regionSelector = selector
                selector.start { [weak self] selection in
                    guard let self else { return }
                    self.regionSelector = nil
                    guard let selection else { return }
                    let display = self.findDisplay(for: selection.screen, in: content) ?? content.displays.first
                    guard let display else {
                        self.showError(CaptureError.noDisplay)
                        return
                    }
                    Task {
                        do {
                            try await Task.sleep(nanoseconds: 150_000_000)
                            let image = try await self.manager.captureRegion(selection.rect, on: display)
                            self.handleCapturedImage(image)
                        } catch {
                            self.showError(error)
                        }
                    }
                }
            } catch {
                showError(error)
            }
        }
    }

    private func findDisplay(for screen: NSScreen?, in content: SCShareableContent) -> SCDisplay? {
        guard let screen else { return nil }
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return content.displays.first(where: { $0.displayID == displayID })
    }

    func captureWindow() {
        Task {
            do {
                let content = try await manager.shareableContent()
                let pickable = content.windows.filter { window in
                    window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                        && window.frame.width > 50
                        && window.frame.height > 50
                        && window.isOnScreen
                }
                let picker = WindowPickerController(windows: pickable)
                self.windowPicker = picker
                picker.start { [weak self] window in
                    guard let self else { return }
                    self.windowPicker = nil
                    guard let window else { return }
                    Task {
                        do {
                            try await Task.sleep(nanoseconds: 100_000_000)
                            let image = try await self.manager.captureWindow(window)
                            self.handleCapturedImage(image)
                        } catch {
                            self.showError(error)
                        }
                    }
                }
            } catch {
                showError(error)
            }
        }
    }

    func toggleVideoRecording() {
        if recorder.isRecording {
            stopVideoRecording()
        } else {
            startFullScreenVideoRecording()
        }
    }

    func toggleRegionVideoRecording() {
        if recorder.isRecording {
            stopVideoRecording()
        } else {
            startRegionVideoRecording()
        }
    }

    private func startFullScreenVideoRecording() {
        Task {
            await ensureMicrophonePermissionOrWarn()
            do {
                let content = try await manager.shareableContent()
                let preferredDisplay = findDisplay(for: NSScreen.main, in: content) ?? content.displays.first
                guard let display = preferredDisplay else {
                    showError(CaptureError.noDisplay)
                    return
                }
                guard let screen = matchingScreen(for: display) else {
                    showError(CaptureError.noDisplay)
                    return
                }
                let region = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
                let excludingApps = klikApps(in: content)
                _ = try await self.recorder.startRecording(
                    region: region,
                    on: display,
                    screen: screen,
                    excludingApps: excludingApps
                )
                self.presentControlBar()
            } catch {
                showError(error)
            }
        }
    }

    private func ensureMicrophonePermissionOrWarn() async {
        let priorStatus = MicrophoneAccess.currentStatus
        let granted = await MicrophoneAccess.request()
        guard !granted else { return }
        if priorStatus == .denied || priorStatus == .restricted {
            showMicrophoneDeniedAlert()
        } else {
            NotificationToast.show(message: "Microphone access not granted — recording without voice", duration: 3)
        }
    }

    private func showMicrophoneDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone access denied"
        alert.informativeText = "Klik needs microphone access to record your voice. The recording will continue with system audio only. To enable it, open System Settings → Privacy & Security → Microphone and turn on Klik."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Continue Without Mic")
        if alert.runModal() == .alertFirstButtonReturn {
            MicrophoneAccess.openPrivacySettings()
        }
    }

    private func startRegionVideoRecording() {
        Task {
            await ensureMicrophonePermissionOrWarn()
            do {
                let content = try await manager.shareableContent()
                let selector = RegionSelectorController()
                self.regionSelector = selector
                selector.start { [weak self] selection in
                    guard let self else { return }
                    self.regionSelector = nil
                    guard let selection else { return }
                    let display = self.findDisplay(for: selection.screen, in: content) ?? content.displays.first
                    guard let display else {
                        self.showError(CaptureError.noDisplay)
                        return
                    }
                    let excludingApps = self.klikApps(in: content)
                    Task {
                        do {
                            try await Task.sleep(nanoseconds: 200_000_000)
                            _ = try await self.recorder.startRecording(
                                region: selection.rect,
                                on: display,
                                screen: selection.screen,
                                excludingApps: excludingApps
                            )
                            self.presentControlBar()
                        } catch {
                            self.showError(error)
                        }
                    }
                }
            } catch {
                showError(error)
            }
        }
    }

    private func klikApps(in content: SCShareableContent) -> [SCRunningApplication] {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.marino.klik"
        return content.applications.filter { $0.bundleIdentifier == bundleID }
    }

    private func matchingScreen(for display: SCDisplay) -> NSScreen? {
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        } ?? NSScreen.main
    }

    private func stopVideoRecording() {
        Task {
            do {
                let url = try await recorder.stopRecording()
                dismissControlBar()
                await handleRecordedVideo(at: url)
            } catch {
                dismissControlBar()
                showError(error)
            }
        }
    }

    private func cancelVideoRecording() {
        Task {
            await recorder.cancelRecording()
            dismissControlBar()
        }
    }

    private func presentControlBar() {
        let bar = RecordingControlBar()
        bar.onStop = { [weak self] in self?.stopVideoRecording() }
        bar.onCancel = { [weak self] in self?.cancelVideoRecording() }
        self.recordingControlBar = bar
        bar.present()
    }

    private func dismissControlBar() {
        recordingControlBar?.dismissBar()
        recordingControlBar = nil
    }

    private func handleRecordedVideo(at url: URL) async {
        let micGranted = MicrophoneAccess.isGranted
        let micSamples = recorder.microphoneSampleCount
        NSLog("Klik: recording finished — micGranted=\(micGranted) micSampleCount=\(micSamples)")
        if micGranted && micSamples == 0 {
            NotificationToast.show(message: "Warning: no microphone audio was captured", duration: 4)
        }

        // If both system audio and mic produced samples (two audio tracks),
        // automatically mix them into one track in-place so downstream tools
        // (HandBrake, Slack uploads, browsers, etc.) get a single-track MP4
        // and don't drop the microphone audio.
        if micSamples > 0 {
            await autoMixAudioTracks(inPlaceAt: url)
        }

        let poster = await VideoPoster.firstFrame(of: url) ?? NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil) ?? NSImage()
        let state = VideoMediaState(fileURL: url, poster: poster, isPendingSave: true)
        QuickAccessOverlayController.show(media: .video(state))
    }

    private func autoMixAudioTracks(inPlaceAt url: URL) async {
        let mixedURL = url.deletingPathExtension().appendingPathExtension("mixed.mp4")
        ProcessingHUD.shared.show(message: "Removing echo + mixing audio…")
        defer { ProcessingHUD.shared.hide() }

        // First try echo cancellation + mix. If anything goes wrong, fall back
        // to the plain track sum so the user still gets a single-track file.
        do {
            try await EchoCancellingMixer.process(inputURL: url, outputURL: mixedURL)
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: mixedURL, to: url)
            NSLog("Klik: echo-cancelled + mixed audio into single track at \(url.path)")
            return
        } catch {
            try? FileManager.default.removeItem(at: mixedURL)
            NSLog("Klik: echo-cancel mix failed (\(error)); falling back to plain mix")
        }

        ProcessingHUD.shared.update(message: "Mixing audio…")
        do {
            try await AudioMixer.mixAudioTracks(inputURL: url, outputURL: mixedURL)
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: mixedURL, to: url)
            NSLog("Klik: plain-mixed audio into single track at \(url.path)")
        } catch {
            try? FileManager.default.removeItem(at: mixedURL)
            NSLog("Klik: plain mix also failed, keeping original two-track audio — \(error)")
        }
    }

    private func handleCapturedImage(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        if Storage.shared.copyToClipboardOnCapture {
            Storage.shared.copyToClipboard(nsImage)
        }

        guard let fileURL = Storage.shared.saveImage(nsImage) else {
            EditorWindowController.show(image: nsImage)
            return
        }

        QuickAccessOverlayController.show(media: .image(nsImage, fileURL: fileURL))
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Klik"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if case CaptureError.noPermission = error {
            alert.addButton(withTitle: "Open Settings")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            alert.runModal()
        }
    }
}
