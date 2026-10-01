import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    static let shared = SettingsWindowController()

    private var folderLabel: NSTextField!
    private var copyCheckbox: NSButton!
    private var autoSaveCheckbox: NSButton!
    private var resolutionPopup: NSPopUpButton!
    private var fpsPopup: NSPopUpButton!
    private var qualityPopup: NSPopUpButton!
    private var stopCheckbox: NSButton!
    private let stopMinutes = NSTextField(string: "10")
    private let stopSeconds = NSTextField(string: "0")
    private let stopFeedback = NSTextField(labelWithString: "")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 610),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings — Klik"
        window.center()
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refreshUI()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let folderTitle = makeLabel("Save Folder", bold: true)
        folderLabel = makeLabel(Storage.shared.saveDirectory.path, bold: false)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.maximumNumberOfLines = 1
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))

        copyCheckbox = NSButton(checkboxWithTitle: "Copy to clipboard after capture", target: self, action: #selector(toggleCopy))
        autoSaveCheckbox = NSButton(checkboxWithTitle: "Auto-save capture (skip editor)", target: self, action: #selector(toggleAutoSave))

        resolutionPopup = recordingPopup(label: "Resolution", help: "Maximum video height. Original keeps native pixels. Smaller regions are never enlarged.")
        fpsPopup = recordingPopup(label: "Frame rate", help: "60 fps targets smoother motion and uses more storage and processing power.")
        qualityPopup = recordingPopup(label: "Quality", help: "High preserves more detail; Smaller file uses a lower bitrate.")

        stopCheckbox = NSButton(checkboxWithTitle: "Automatically stop recording", target: self, action: #selector(changeStopSettings))
        for (field, label) in [(stopMinutes, "Automatic stop minutes"), (stopSeconds, "Automatic stop seconds")] {
            field.delegate = self
            field.setAccessibilityLabel(label)
            field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        }
        let durationRow = NSStackView(views: [stopMinutes, makeLabel("minutes", bold: false), stopSeconds, makeLabel("seconds", bold: false)])
        durationRow.spacing = 8
        stopFeedback.font = .systemFont(ofSize: 12)
        stopFeedback.textColor = .labelColor

        let hotkeysTitle = makeLabel("Keyboard Shortcuts", bold: true)
        let hotkeysList = makeLabel("⇧⌘2 — Capture Region\n⇧⌘3 — Capture Full Screen\n⇧⌘4 — Capture Window\n⇧⌘5 — Record Video (Full Screen)", bold: false)

        let stack = NSStackView(views: [
            folderTitle,
            row(folderLabel, chooseButton),
            spacer(),
            copyCheckbox,
            autoSaveCheckbox,
            spacer(),
            makeLabel("Recording", bold: true),
            row(makeLabel("Resolution", bold: false), resolutionPopup),
            row(makeLabel("Frame rate", bold: false), fpsPopup),
            row(makeLabel("Quality", bold: false), qualityPopup),
            makeLabel("Previous settings: 1080p / 30 fps / Standard", bold: false),
            makeLabel("Saved automatically. Applies to the next recording.", bold: false),
            stopCheckbox,
            durationRow,
            stopFeedback,
            makeLabel("Counts elapsed recording time, including microphone mute.", bold: false),
            makeLabel("No pause control. Stops and keeps the video for saving.", bold: false),
            spacer(),
            hotkeysTitle,
            hotkeysList,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])

        window?.contentView = container
    }

    private func refreshUI() {
        refreshRecordingUI()
        let stop = RecordingStopSettings()
        stopCheckbox.state = stop.enabled ? .on : .off
        stopMinutes.stringValue = String(stop.seconds / 60)
        stopSeconds.stringValue = String(stop.seconds % 60)
        updateStopFields()
        folderLabel.stringValue = Storage.shared.saveDirectory.path
        copyCheckbox.state = Storage.shared.copyToClipboardOnCapture ? .on : .off
        autoSaveCheckbox.state = Storage.shared.autoSaveOnCapture ? .on : .off
    }

    private func recordingPopup(label: String, help: String) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.target = self
        popup.action = #selector(changeRecordingSettings)
        popup.toolTip = help
        popup.setAccessibilityLabel(label)
        popup.widthAnchor.constraint(equalToConstant: 240).isActive = true
        return popup
    }

    private func refreshRecordingUI() {
        let settings = RecordingSettings()
        configure(resolutionPopup, titles: RecordingSettings.Resolution.allCases.map { $0.title },
                  selected: RecordingSettings.Resolution.allCases.firstIndex(of: settings.resolution) ?? 1)
        configure(fpsPopup, titles: ["30 fps", "60 fps"], selected: settings.fps == 60 ? 1 : 0)
        configure(qualityPopup, titles: RecordingSettings.Quality.allCases.map { $0.title },
                  selected: RecordingSettings.Quality.allCases.firstIndex(of: settings.quality) ?? 1)
    }

    private func configure(_ popup: NSPopUpButton, titles: [String], selected: Int) {
        popup.removeAllItems()
        popup.addItems(withTitles: titles.enumerated().map { index, title in
            title + (index == selected ? " (current)" : "")
        })
        popup.selectItem(at: selected)
    }

    @objc private func changeRecordingSettings() {
        var settings = RecordingSettings()
        settings.resolution = RecordingSettings.Resolution.allCases[resolutionPopup.indexOfSelectedItem]
        settings.fps = fpsPopup.indexOfSelectedItem == 1 ? 60 : 30
        settings.quality = RecordingSettings.Quality.allCases[qualityPopup.indexOfSelectedItem]
        settings.save()
        refreshRecordingUI()
    }

    func controlTextDidChange(_ obj: Notification) { changeStopSettings() }

    @objc private func changeStopSettings() {
        var settings = RecordingStopSettings()
        let valid = RecordingStopSettings.duration(minutes: stopMinutes.stringValue, seconds: stopSeconds.stringValue)
        settings.enabled = stopCheckbox.state == .on && valid != nil
        if let valid { settings.seconds = valid }
        settings.save()
        updateStopFields()
    }

    private func updateStopFields() {
        let enabled = stopCheckbox.state == .on
        stopMinutes.isEnabled = enabled
        stopSeconds.isEnabled = enabled
        let valid = RecordingStopSettings.duration(minutes: stopMinutes.stringValue, seconds: stopSeconds.stringValue) != nil
        stopFeedback.stringValue = enabled && !valid
            ? "Enter 1 second to 1440 minutes. Seconds: 0–59. Timer is off."
            : "Timer " + (enabled ? "saved for the next recording." : "off. Duration: 1 second to 1440 minutes.")
    }

    private func makeLabel(_ text: String, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold
            ? NSFont.systemFont(ofSize: 13, weight: .semibold)
            : NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = bold ? .labelColor : .secondaryLabelColor
        return label
    }

    private func row(_ a: NSView, _ b: NSView) -> NSView {
        let row = NSStackView(views: [a, b])
        row.orientation = .horizontal
        row.spacing = 12
        a.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func spacer() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return v
    }

    @objc private func chooseFolder() {
        if Storage.shared.chooseSaveDirectory() {
            folderLabel.stringValue = Storage.shared.saveDirectory.path
        }
    }

    @objc private func toggleCopy() {
        Storage.shared.copyToClipboardOnCapture = (copyCheckbox.state == .on)
    }

    @objc private func toggleAutoSave() {
        Storage.shared.autoSaveOnCapture = (autoSaveCheckbox.state == .on)
    }
}
