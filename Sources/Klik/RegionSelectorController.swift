import AppKit

struct RegionSelection {
    let rect: CGRect
    let screen: NSScreen
}

@MainActor
final class RegionSelectorController {
    private var windows: [NSWindow] = []
    private var completion: ((RegionSelection?) -> Void)?

    func start(completion: @escaping (RegionSelection?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.25)
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.hasShadow = false

            let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenFrame = screen.frame
            view.onCommit = { [weak self] rect in
                self?.finish(selection: RegionSelection(rect: rect, screen: screen))
            }
            view.onCancel = { [weak self] in
                self?.finish(selection: nil)
            }
            window.contentView = view
            window.makeFirstResponder(view)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
    }

    private func finish(selection: RegionSelection?) {
        NSCursor.pop()
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        let cb = completion
        completion = nil
        if let s = selection, s.rect.width > 4, s.rect.height > 4 {
            cb?(s)
        } else {
            cb?(nil)
        }
    }
}

private final class RegionSelectionView: NSView {
    var screenFrame: NSRect = .zero
    var onCommit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(origin: startPoint!, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, p.x),
            y: min(start.y, p.y),
            width: abs(p.x - start.x),
            height: abs(p.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width > 2, rect.height > 2 else {
            onCancel?()
            return
        }
        let displayRelative = CGRect(
            x: rect.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        onCommit?(displayRelative)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = currentRect else { return }

        NSColor.clear.setFill()
        rect.fill()

        let border = NSBezierPath(rect: rect)
        NSColor.systemBlue.setStroke()
        border.lineWidth = 1.5
        border.stroke()

        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let labelOrigin = NSPoint(x: rect.maxX - size.width - 6, y: rect.minY - size.height - 6)
        (label as NSString).draw(at: labelOrigin, withAttributes: attrs)
    }
}
