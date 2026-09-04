import AppKit
import UniformTypeIdentifiers

@MainActor
final class QuickAccessOverlayController: NSWindowController, NSWindowDelegate {
    private static var stack: [QuickAccessOverlayController] = []
    private static let thumbMaxSize = CGSize(width: 240, height: 180)
    private static let edgeInset: CGFloat = 24
    private static let stackSpacing: CGFloat = 12

    private let media: Media
    private let thumbSize: CGSize

    init(media: Media) {
        self.media = media
        self.thumbSize = Self.fittedSize(for: media.displayImage.size, maxSize: Self.thumbMaxSize)

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame = NSRect(
            x: screen.visibleFrame.origin.x + Self.edgeInset,
            y: screen.visibleFrame.origin.y + Self.edgeInset,
            width: thumbSize.width,
            height: thumbSize.height
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false

        super.init(window: window)
        window.delegate = self

        let view = QuickAccessOverlayView(media: media)
        view.onPrimary = { [weak self] in self?.handlePrimaryAction() }
        view.onSave = { [weak self] in self?.handleSaveAction() }
        view.onClose = { [weak self] in self?.dismissOverlay() }
        view.onContextOpen = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.media.fileURL)
        }
        view.onContextReveal = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.activateFileViewerSelecting([self.media.fileURL])
        }
        view.onContextConvertToGIF = { [weak self] in
            guard let self, case .video(let state) = self.media else { return }
            self.convertToGIF(videoURL: state.fileURL)
        }
        view.onContextMixAudio = { [weak self] in
            guard let self, case .video(let state) = self.media else { return }
            self.mixAudioToSingleTrack(state: state)
        }
        view.onContextEdit = { [weak self] in
            guard let self, case .image = self.media else { return }
            EditorWindowController.show(image: self.media.loadFullImage())
            self.dismissOverlay()
        }
        view.onContextCopyToClipboard = { [weak self] in
            guard let self else { return }
            switch self.media {
            case .image:
                Storage.shared.copyToClipboard(self.media.loadFullImage())
                NotificationToast.show(message: "Image copied to clipboard")
            case .video(let state):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([state.fileURL as NSURL])
                NotificationToast.show(message: "File path copied to clipboard")
            }
        }
        window.contentView = view
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func show(media: Media) {
        let c = QuickAccessOverlayController(media: media)
        stack.insert(c, at: 0)
        layoutStack(skipAnimating: c)
        c.presentAnimated()
    }

    private static func layoutStack(skipAnimating: QuickAccessOverlayController? = nil) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        var y = screen.visibleFrame.origin.y + edgeInset
        for controller in stack {
            guard let window = controller.window else { continue }
            let target = NSRect(
                x: screen.visibleFrame.origin.x + edgeInset,
                y: y,
                width: controller.thumbSize.width,
                height: controller.thumbSize.height
            )
            if controller === skipAnimating {
                window.setFrame(target, display: false)
            } else if window.frame != target {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.24
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(target, display: true)
                }
            }
            y += target.height + stackSpacing
        }
    }

    private func presentAnimated() {
        guard let window = self.window else { return }
        window.alphaValue = 0
        let originalFrame = window.frame
        var startFrame = originalFrame
        startFrame.origin.x -= 24
        window.setFrame(startFrame, display: false)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(originalFrame, display: true)
        }
    }

    func dismissOverlay() {
        guard let window = self.window else { return }
        cleanupPendingTempFile()
        Self.stack.removeAll { $0 === self }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
            }
        })
        Self.layoutStack()
    }

    func windowWillClose(_ notification: Notification) {
        cleanupPendingTempFile()
        Self.stack.removeAll { $0 === self }
        Self.layoutStack()
    }

    private func cleanupPendingTempFile() {
        guard case .video(let state) = media, state.isPendingSave else { return }
        try? FileManager.default.removeItem(at: state.fileURL)
    }

    private func handlePrimaryAction() {
        switch media {
        case .image:
            EditorWindowController.show(image: media.loadFullImage())
            dismissOverlay()
        case .video(let state):
            // Opening a recording means the user chose to keep it. Move it
            // out of the temporary directory before handing it to QuickTime.
            if state.isPendingSave,
               let newURL = Storage.shared.moveVideoToFinalLocation(from: state.fileURL) {
                state.fileURL = newURL
                state.isPendingSave = false
            }
            NSWorkspace.shared.open(state.fileURL)
        }
    }

    private func handleSaveAction() {
        switch media {
        case .image(_, let url):
            NotificationToast.show(message: "Already saved: \(url.lastPathComponent)")
        case .video(let state):
            guard state.isPendingSave else {
                NotificationToast.show(message: "Already saved: \(state.fileURL.lastPathComponent)")
                return
            }
            guard let newURL = Storage.shared.moveVideoToFinalLocation(from: state.fileURL) else {
                NotificationToast.show(message: "Save failed", duration: 3)
                return
            }
            state.fileURL = newURL
            state.isPendingSave = false
            NotificationToast.show(message: "Saved: \(newURL.lastPathComponent)")
        }
    }

    private func mixAudioToSingleTrack(state: VideoMediaState) {
        let inputURL = state.fileURL
        let mixedURL = inputURL.deletingPathExtension().appendingPathExtension("mixed.mp4")
        NotificationToast.show(message: "Mixing audio tracks…", duration: 1.0)
        Task.detached {
            do {
                try await AudioMixer.mixAudioTracks(inputURL: inputURL, outputURL: mixedURL)
                try? FileManager.default.removeItem(at: inputURL)
                try FileManager.default.moveItem(at: mixedURL, to: inputURL)
                await MainActor.run {
                    NotificationToast.show(message: "Audio mixed to single track ✓")
                }
            } catch {
                try? FileManager.default.removeItem(at: mixedURL)
                await MainActor.run {
                    NotificationToast.show(message: "Mix failed: \(error.localizedDescription)", duration: 3)
                }
            }
        }
    }

    private func convertToGIF(videoURL: URL) {
        let gifURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
        NotificationToast.show(message: "Converting to GIF…", duration: 1.0)
        Task.detached {
            do {
                try await GIFConverter.convert(videoURL: videoURL, outputURL: gifURL)
                await MainActor.run {
                    NotificationToast.show(message: "GIF saved: \(gifURL.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([gifURL])
                }
            } catch {
                await MainActor.run {
                    NotificationToast.show(message: "GIF error: \(error.localizedDescription)", duration: 3)
                }
            }
        }
    }

    private static func fittedSize(for source: CGSize, maxSize: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return maxSize }
        let scale = min(maxSize.width / source.width, maxSize.height / source.height, 1.0)
        return CGSize(width: max(source.width * scale, 80), height: max(source.height * scale, 60))
    }
}

private final class QuickAccessOverlayView: NSView, NSDraggingSource {
    let media: Media

    var onPrimary: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    var onContextOpen: (() -> Void)?
    var onContextReveal: (() -> Void)?
    var onContextConvertToGIF: (() -> Void)?
    var onContextMixAudio: (() -> Void)?
    var onContextEdit: (() -> Void)?
    var onContextCopyToClipboard: (() -> Void)?

    private var hovering = false
    private var trackingArea: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var dragInProgress = false

    private let primaryButton = NSButton()
    private let saveButton = NSButton()
    private let buttonStack = NSStackView()
    private let closeButton = NSButton()
    private let imageLayer = CALayer()
    private let backgroundLayer = CALayer()
    private let hoverOverlayLayer = CALayer()
    private let videoBadgeLayer = CALayer()

    init(media: Media) {
        self.media = media
        super.init(frame: .zero)
        wantsLayer = true
        setupLayers()
        setupButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        backgroundLayer.backgroundColor = NSColor(white: 0.05, alpha: 1.0).cgColor
        backgroundLayer.cornerRadius = 10
        backgroundLayer.masksToBounds = true
        backgroundLayer.borderColor = NSColor(white: 1, alpha: 0.18).cgColor
        backgroundLayer.borderWidth = 1
        layer?.addSublayer(backgroundLayer)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.cornerRadius = 10
        imageLayer.masksToBounds = true
        if let cg = media.displayImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            imageLayer.contents = cg
        }
        layer?.addSublayer(imageLayer)

        hoverOverlayLayer.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
        hoverOverlayLayer.cornerRadius = 10
        hoverOverlayLayer.opacity = 0
        layer?.addSublayer(hoverOverlayLayer)

        if media.isVideo {
            videoBadgeLayer.contents = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 36, weight: .semibold))
            videoBadgeLayer.contentsGravity = .center
            videoBadgeLayer.opacity = 0.85
            layer?.addSublayer(videoBadgeLayer)
        }
    }

    private func setupButtons() {
        primaryButton.title = media.isVideo ? "Open" : "Edit"
        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .regular
        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)
        primaryButton.image = NSImage(systemSymbolName: media.isVideo ? "play.fill" : "pencil.tip", accessibilityDescription: nil)
        primaryButton.imagePosition = .imageLeft

        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .regular
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        saveButton.imagePosition = .imageLeft
        saveButton.keyEquivalent = "\r"

        buttonStack.orientation = .vertical
        buttonStack.spacing = 6
        buttonStack.alignment = .centerX
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.alphaValue = 0
        buttonStack.addArrangedSubview(primaryButton)
        if media.isVideo {
            buttonStack.addArrangedSubview(saveButton)
        }
        addSubview(buttonStack)

        closeButton.title = ""
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
            .withSymbolConfiguration(symbolConfig)
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.95)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.alphaValue = 0
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            buttonStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
        imageLayer.frame = bounds
        hoverOverlayLayer.frame = bounds
        let badgeSize: CGFloat = 44
        videoBadgeLayer.frame = NSRect(
            x: bounds.midX - badgeSize/2,
            y: bounds.midY - badgeSize/2,
            width: badgeSize,
            height: badgeSize
        )
    }

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

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    private func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            hoverOverlayLayer.opacity = value ? 1 : 0
            videoBadgeLayer.opacity = value ? 0 : (media.isVideo ? 0.85 : 0)
            buttonStack.animator().alphaValue = value ? 1 : 0
            closeButton.animator().alphaValue = value ? 1 : 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragInProgress = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !dragInProgress else { return }
        let p = event.locationInWindow
        let distance = hypot(p.x - start.x, p.y - start.y)
        guard distance > 6 else { return }

        dragInProgress = true
        startDragSession(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        dragInProgress = false
    }

    private func startDragSession(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: media.fileURL as NSURL)
        let dragImage = thumbnailForDrag()
        let dragSize = NSSize(
            width: bounds.width * 0.8,
            height: bounds.height * 0.8
        )
        let dragRect = NSRect(
            x: (bounds.width - dragSize.width) / 2,
            y: (bounds.height - dragSize.height) / 2,
            width: dragSize.width,
            height: dragSize.height
        )
        item.setDraggingFrame(dragRect, contents: dragImage)

        beginDraggingSession(with: [item], event: event, source: self)
    }

    private func thumbnailForDrag() -> NSImage {
        let size = NSSize(width: bounds.width * 0.8, height: bounds.height * 0.8)
        let img = NSImage(size: size)
        img.lockFocus()
        media.displayImage.draw(in: NSRect(origin: .zero, size: size))
        img.unlockFocus()
        return img
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .generic]
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        Task { @MainActor [weak self] in
            self?.dragInProgress = false
            if operation != [] {
                try? await Task.sleep(nanoseconds: 200_000_000)
                self?.window?.close()
            }
        }
    }

    @objc private func primaryTapped() { onPrimary?() }
    @objc private func saveTapped() { onSave?() }
    @objc private func closeTapped() { onClose?() }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        if media.isVideo {
            menu.addItem(makeMenuItem("Open", #selector(ctxOpen)))
            menu.addItem(makeMenuItem("Save to Desktop", #selector(ctxSave)))
            menu.addItem(makeMenuItem("Reveal in Finder", #selector(ctxReveal)))
            menu.addItem(makeMenuItem("Copy Path", #selector(ctxCopy)))
            menu.addItem(.separator())
            menu.addItem(makeMenuItem("Mix Audio to Single Track", #selector(ctxMixAudio)))
            menu.addItem(makeMenuItem("Convert to GIF", #selector(ctxToGIF)))
        } else {
            menu.addItem(makeMenuItem("Edit", #selector(ctxEdit)))
            menu.addItem(makeMenuItem("Copy Image", #selector(ctxCopy)))
            menu.addItem(makeMenuItem("Reveal in Finder", #selector(ctxReveal)))
        }
        menu.addItem(.separator())
        menu.addItem(makeMenuItem("Close", #selector(closeTapped)))
        for item in menu.items where item.target == nil { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func makeMenuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func ctxOpen()     { onContextOpen?() }
    @objc private func ctxSave()     { onSave?() }
    @objc private func ctxReveal()   { onContextReveal?() }
    @objc private func ctxToGIF()    { onContextConvertToGIF?() }
    @objc private func ctxMixAudio() { onContextMixAudio?() }
    @objc private func ctxEdit()     { onContextEdit?() }
    @objc private func ctxCopy()     { onContextCopyToClipboard?() }
}
