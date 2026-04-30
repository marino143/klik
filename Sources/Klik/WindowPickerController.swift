import AppKit
import ScreenCaptureKit

@MainActor
final class WindowPickerController {
    private let windows: [SCWindow]
    private var overlayWindows: [NSWindow] = []
    private var completion: ((SCWindow?) -> Void)?

    init(windows: [SCWindow]) {
        self.windows = windows
    }

    func start(completion: @escaping (SCWindow?) -> Void) {
        self.completion = completion
        guard !windows.isEmpty else {
            completion(nil)
            return
        }
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.15)
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.hasShadow = false

            let view = WindowPickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screen = screen
            view.allWindows = windows
            view.onPick = { [weak self] picked in
                self?.finish(picked: picked)
            }
            view.onCancel = { [weak self] in
                self?.finish(picked: nil)
            }
            window.contentView = view
            window.makeFirstResponder(view)
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(picked: SCWindow?) {
        for w in overlayWindows {
            w.orderOut(nil)
        }
        overlayWindows.removeAll()
        let cb = completion
        completion = nil
        cb?(picked)
    }
}

private final class WindowPickerView: NSView {
    var screen: NSScreen?
    var allWindows: [SCWindow] = []
    var onPick: ((SCWindow) -> Void)?
    var onCancel: (() -> Void)?

    private var hoveredWindow: SCWindow?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        hoveredWindow = windowUnder(point: p)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let w = windowUnder(point: p) {
            onPick?(w)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private func windowUnder(point viewPoint: NSPoint) -> SCWindow? {
        guard let screen else { return nil }
        let globalPoint = NSPoint(
            x: screen.frame.origin.x + viewPoint.x,
            y: screen.frame.origin.y + viewPoint.y
        )
        let topLeftPoint = NSPoint(
            x: globalPoint.x,
            y: NSScreen.screens.first!.frame.height - globalPoint.y
        )
        return allWindows
            .filter { $0.frame.contains(topLeftPoint) }
            .sorted { $0.windowLayer < $1.windowLayer }
            .first
    }

    private func windowFrameInView(_ window: SCWindow) -> NSRect? {
        guard let screen else { return nil }
        let primaryHeight = NSScreen.screens.first!.frame.height
        let topLeft = window.frame
        let globalY = primaryHeight - topLeft.origin.y - topLeft.height
        let viewX = topLeft.origin.x - screen.frame.origin.x
        let viewY = globalY - screen.frame.origin.y
        return NSRect(x: viewX, y: viewY, width: topLeft.width, height: topLeft.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let hovered = hoveredWindow,
              let rect = windowFrameInView(hovered) else { return }

        NSColor.systemBlue.withAlphaComponent(0.2).setFill()
        rect.fill()
        let border = NSBezierPath(rect: rect)
        NSColor.systemBlue.setStroke()
        border.lineWidth = 2.5
        border.stroke()

        if let title = hovered.title ?? hovered.owningApplication?.applicationName {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let size = (title as NSString).size(withAttributes: attrs)
            let bg = NSRect(
                x: rect.midX - size.width/2 - 8,
                y: rect.midY - size.height/2 - 4,
                width: size.width + 16,
                height: size.height + 8
            )
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: bg, xRadius: 6, yRadius: 6).fill()
            (title as NSString).draw(at: NSPoint(x: bg.minX + 8, y: bg.minY + 4), withAttributes: attrs)
        }
    }
}
