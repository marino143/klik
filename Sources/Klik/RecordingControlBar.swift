import AppKit

@MainActor
final class RecordingControlBar: NSWindowController, NSWindowDelegate {
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    private let timerLabel = NSTextField(labelWithString: "00:00")
    private let recIndicator = NSView()
    private var ticker: Timer?
    private var startedAt: Date?

    init() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let size = NSSize(width: 200, height: 38)
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - 8,
            width: size.width,
            height: size.height
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
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true

        super.init(window: window)
        window.delegate = self
        window.contentView = buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        startedAt = Date()
        startTicker()
        showWindow(nil)
        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window?.animator().alphaValue = 1
        }
    }

    func dismissBar() {
        stopTicker()
        guard let window = self.window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    private func buildView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.05, alpha: 0.92).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderColor = NSColor(white: 1, alpha: 0.15).cgColor
        container.layer?.borderWidth = 1

        recIndicator.wantsLayer = true
        recIndicator.layer?.backgroundColor = NSColor.systemRed.cgColor
        recIndicator.layer?.cornerRadius = 5
        recIndicator.translatesAutoresizingMaskIntoConstraints = false

        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timerLabel.textColor = .white
        timerLabel.translatesAutoresizingMaskIntoConstraints = false

        let stopButton = NSButton(image: NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")!, target: self, action: #selector(stopTapped))
        stopButton.bezelStyle = .circular
        stopButton.isBordered = false
        stopButton.contentTintColor = .systemRed
        stopButton.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel")!, target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .circular
        cancelButton.isBordered = false
        cancelButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(recIndicator)
        container.addSubview(timerLabel)
        container.addSubview(stopButton)
        container.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            recIndicator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            recIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            recIndicator.widthAnchor.constraint(equalToConstant: 10),
            recIndicator.heightAnchor.constraint(equalToConstant: 10),

            timerLabel.leadingAnchor.constraint(equalTo: recIndicator.trailingAnchor, constant: 8),
            timerLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            stopButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -4),
            stopButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 28),
            stopButton.heightAnchor.constraint(equalToConstant: 28),

            cancelButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            cancelButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 22),
            cancelButton.heightAnchor.constraint(equalToConstant: 22),
        ])

        startBlinkAnimation()
        return container
    }

    private func startBlinkAnimation() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.3
        anim.duration = 0.6
        anim.autoreverses = true
        anim.repeatCount = .infinity
        recIndicator.layer?.add(anim, forKey: "blink")
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let started = startedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(started))
        let mm = elapsed / 60
        let ss = elapsed % 60
        timerLabel.stringValue = String(format: "%02d:%02d", mm, ss)
    }

    @objc private func stopTapped() { onStop?() }
    @objc private func cancelTapped() { onCancel?() }
}
