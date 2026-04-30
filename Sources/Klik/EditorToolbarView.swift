import AppKit

final class EditorToolbarView: NSView {
    var onToolChange: ((Tool) -> Void)?
    var onColorChange: ((NSColor) -> Void)?
    var onUndo: (() -> Void)?
    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPin: (() -> Void)?

    private var toolButtons: [Tool: NSButton] = [:]
    private var colorWell: NSColorWell!

    private let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemBlue, .systemPurple,
        .black, .white
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.18, alpha: 1.0).cgColor
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let toolStack = NSStackView()
        toolStack.orientation = .horizontal
        toolStack.spacing = 4
        toolStack.translatesAutoresizingMaskIntoConstraints = false

        for tool in Tool.allCases {
            let button = makeToolButton(tool: tool)
            toolButtons[tool] = button
            toolStack.addArrangedSubview(button)
        }

        let separator1 = makeSeparator()
        let undoButton = makeIconButton(symbol: "arrow.uturn.backward", action: #selector(undoTapped))

        let colorStack = NSStackView()
        colorStack.orientation = .horizontal
        colorStack.spacing = 4
        colorStack.translatesAutoresizingMaskIntoConstraints = false

        for color in palette {
            colorStack.addArrangedSubview(makeColorSwatch(color: color))
        }

        let separator2 = makeSeparator()
        let copyButton = makeTextButton(title: "Copy", action: #selector(copyTapped))
        let saveButton = makeTextButton(title: "Save", action: #selector(saveTapped))
        let pinButton = makeTextButton(title: "Pin", action: #selector(pinTapped))

        let mainStack = NSStackView(views: [toolStack, separator1, undoButton, colorStack, separator2, copyButton, saveButton, pinButton])
        mainStack.orientation = .horizontal
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            separator1.heightAnchor.constraint(equalToConstant: 28),
            separator2.heightAnchor.constraint(equalToConstant: 28),
        ])

        selectTool(.select)
    }

    private func makeToolButton(tool: Tool) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.label)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(toolTapped(_:))
        button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
        button.toolTip = tool.label
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    private func makeIconButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func makeTextButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    private func makeSeparator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.35, alpha: 1.0).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func makeColorSwatch(color: NSColor) -> NSView {
        let button = ColorSwatchButton(color: color)
        button.target = self
        button.action = #selector(colorTapped(_:))
        return button
    }

    @objc private func toolTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let tool = Tool(rawValue: raw) else { return }
        selectTool(tool)
        onToolChange?(tool)
    }

    private func selectTool(_ tool: Tool) {
        for (t, btn) in toolButtons {
            btn.contentTintColor = (t == tool) ? .controlAccentColor : .secondaryLabelColor
        }
    }

    @objc private func colorTapped(_ sender: ColorSwatchButton) {
        onColorChange?(sender.color)
    }

    @objc private func undoTapped() { onUndo?() }
    @objc private func saveTapped() { onSave?() }
    @objc private func copyTapped() { onCopy?() }
    @objc private func pinTapped() { onPin?() }
}

private final class ColorSwatchButton: NSButton {
    let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        title = ""
        bezelStyle = .smallSquare
        isBordered = false
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 11
        layer?.borderColor = NSColor(white: 1, alpha: 0.3).cgColor
        layer?.borderWidth = 1
    }
}
