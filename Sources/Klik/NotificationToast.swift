import AppKit

@MainActor
enum NotificationToast {
    private static var current: NSWindow?

    static func show(message: String, duration: TimeInterval = 1.6) {
        current?.orderOut(nil)
        guard let screen = NSScreen.main else { return }

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0, alpha: 0.85).cgColor
        container.layer?.cornerRadius = 10
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            container.heightAnchor.constraint(equalToConstant: 44),
        ])

        let labelSize = label.intrinsicContentSize
        let width = labelSize.width + 36
        let height: CGFloat = 44

        let frame = NSRect(
            x: screen.visibleFrame.midX - width/2,
            y: screen.visibleFrame.minY + 80,
            width: width,
            height: height
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
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = container
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
        })

        current = window

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak window] in
            guard let window else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
                if current === window { current = nil }
            })
        }
    }
}
