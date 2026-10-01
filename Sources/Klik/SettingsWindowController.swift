import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var folderLabel: NSTextField!
    private var copyCheckbox: NSButton!
    private var autoSaveCheckbox: NSButton!
    private var resolutionPopup: NSPopUpButton!
    private var fpsPopup: NSPopUpButton!
    private var qualityPopup: NSPopUpButton!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 490),
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
