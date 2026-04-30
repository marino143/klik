import AppKit

@MainActor
final class PinnedWindowController: NSWindowController, NSWindowDelegate {
    private static var pinned: [PinnedWindowController] = []

    init(image: NSImage) {
        let size = NSSize(
            width: min(image.size.width / 2, 800),
            height: min(image.size.height / 2, 600)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = true

        let imageView = PinnedImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor(white: 1, alpha: 0.2).cgColor
        container.layer?.borderWidth = 1
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        window.contentView = container
        window.center()

        super.init(window: window)
        window.delegate = self
        imageView.onClose = { [weak self] in self?.close() }
        imageView.onCopy = { [weak self] in self?.copyImage() }
        imageView.onSave = { [weak self] in self?.saveImage() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func pin(image: NSImage) {
        let controller = PinnedWindowController(image: image)
        pinned.append(controller)
        controller.showWindow(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Self.pinned.removeAll { $0 === self }
    }

    private func copyImage() {
        guard let imageView = window?.contentView?.subviews.first as? PinnedImageView,
              let image = imageView.image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        NotificationToast.show(message: "Copied to clipboard")
    }

    private func saveImage() {
        guard let imageView = window?.contentView?.subviews.first as? PinnedImageView,
              let image = imageView.image,
              let url = Storage.shared.saveImage(image) else { return }
        NotificationToast.show(message: "Saved: \(url.lastPathComponent)")
    }
}

private final class PinnedImageView: NSImageView {
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    private var hovering = false
    private var trackingArea: NSTrackingArea?

    init(image: NSImage) {
        super.init(frame: .zero)
        self.image = image
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(menuCopy), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Save…", action: #selector(menuSave), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Close", action: #selector(menuClose), keyEquivalent: "w"))
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func menuClose() { onClose?() }
    @objc private func menuCopy() { onCopy?() }
    @objc private func menuSave() { onSave?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hovering else { return }
        let badge = NSRect(x: bounds.maxX - 28, y: bounds.maxY - 28, width: 20, height: 20)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(ovalIn: badge).fill()
        let xPath = NSBezierPath()
        xPath.move(to: NSPoint(x: badge.minX + 6, y: badge.minY + 6))
        xPath.line(to: NSPoint(x: badge.maxX - 6, y: badge.maxY - 6))
        xPath.move(to: NSPoint(x: badge.minX + 6, y: badge.maxY - 6))
        xPath.line(to: NSPoint(x: badge.maxX - 6, y: badge.minY + 6))
        NSColor.white.setStroke()
        xPath.lineWidth = 1.5
        xPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let badge = NSRect(x: bounds.maxX - 28, y: bounds.maxY - 28, width: 20, height: 20)
        if hovering && badge.contains(p) {
            onClose?()
            return
        }
        window?.performDrag(with: event)
    }
}
