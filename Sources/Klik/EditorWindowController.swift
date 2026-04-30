import AppKit

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openControllers: [EditorWindowController] = []

    let canvasView: AnnotationCanvasView
    private let toolbarView: EditorToolbarView

    init(image: NSImage) {
        self.canvasView = AnnotationCanvasView(image: image)
        self.toolbarView = EditorToolbarView()

        let imageSize = image.size
        let maxWidth: CGFloat = 1200
        let maxHeight: CGFloat = 800
        let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1.0)
        let initialSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale + 56)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Klik — Editor"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()

        super.init(window: window)
        window.delegate = self

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.12, alpha: 1.0)
        scrollView.documentView = canvasView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = toolbarView
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.onToolChange = { [weak self] tool in
            self?.canvasView.currentTool = tool
        }
        toolbar.onColorChange = { [weak self] color in
            self?.canvasView.style.color = color
        }
        toolbar.onUndo = { [weak self] in
            self?.canvasView.undo()
        }
        toolbar.onSave = { [weak self] in self?.save() }
        toolbar.onCopy = { [weak self] in self?.copy() }
        toolbar.onPin = { [weak self] in self?.pin() }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 56),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        window.contentView = container
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func show(image: NSImage) {
        let controller = EditorWindowController(image: image)
        openControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }

    private func save() {
        guard let image = canvasView.renderedImage() else { return }
        let savedURL = Storage.shared.saveImage(image)
        if let url = savedURL {
            NotificationToast.show(message: "Saved: \(url.lastPathComponent)")
        }
    }

    private func copy() {
        guard let image = canvasView.renderedImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        NotificationToast.show(message: "Copied to clipboard")
    }

    private func pin() {
        guard let image = canvasView.renderedImage() else { return }
        PinnedWindowController.pin(image: image)
        window?.close()
    }
}
