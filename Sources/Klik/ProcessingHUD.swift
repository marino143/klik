import AppKit

/// A small floating HUD with a spinner, shown while a long-running operation
/// (e.g. echo cancellation + audio mixing) is in progress. Unlike
/// NotificationToast it does not auto-dismiss — call `hide()` when done.
@MainActor
final class ProcessingHUD {
    static let shared = ProcessingHUD()

    private var window: NSWindow?

    func show(message: String) {
        hide()
        guard let screen = NSScreen.main else { return }

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0, alpha: 0.85).cgColor
        container.layer?.cornerRadius = 10
        container.addSubview(spinner)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            container.heightAnchor.constraint(equalToConstant: 44),
        ])

        let labelSize = label.intrinsicContentSize
        let width = 16 + 16 + 10 + labelSize.width + 18
        let frame = NSRect(
            x: screen.visibleFrame.midX - width / 2,
            y: screen.visibleFrame.minY + 80,
            width: width,
            height: 44
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.contentView = container
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
        }
        self.window = window
    }

    func update(message: String) {
        guard let label = window?.contentView?.subviews.compactMap({ $0 as? NSTextField }).first else { return }
        label.stringValue = message
    }

    func hide() {
        guard let window = self.window else { return }
        self.window = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}
