import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var folderLabel: NSTextField!
    private var copyCheckbox: NSButton!
    private var autoSaveCheckbox: NSButton!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
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

        let hotkeysTitle = makeLabel("Keyboard Shortcuts", bold: true)
        let hotkeysList = makeLabel("⇧⌘2 — Capture Region\n⇧⌘3 — Capture Full Screen\n⇧⌘4 — Capture Window\n⇧⌘5 — Record Video (Full Screen)", bold: false)

        let stack = NSStackView(views: [
            folderTitle,
            row(folderLabel, chooseButton),
            spacer(),
            copyCheckbox,
            autoSaveCheckbox,
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
        folderLabel.stringValue = Storage.shared.saveDirectory.path
        copyCheckbox.state = Storage.shared.copyToClipboardOnCapture ? .on : .off
        autoSaveCheckbox.state = Storage.shared.autoSaveOnCapture ? .on : .off
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            Storage.shared.saveDirectory = url
            folderLabel.stringValue = url.path
        }
    }

    @objc private func toggleCopy() {
        Storage.shared.copyToClipboardOnCapture = (copyCheckbox.state == .on)
    }

    @objc private func toggleAutoSave() {
        Storage.shared.autoSaveOnCapture = (autoSaveCheckbox.state == .on)
    }
}
