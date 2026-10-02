import AppKit

/// Opt-in, recording-control-only trace. No event monitors or user content.
/// Uses the existing rotating logger (current file plus five 1 MB archives).
@MainActor
final class RecordingStopDiagnostics {
    enum Source: String { case bar, menuOrShortcut, regionMenu, automatic }
    enum Phase: String {
        case sessionStarted, barPresented, barDismissed, stoppingShown
        case trackingBegin, trackingEnd, action, callback
        case coordinatorRequest, coordinatorRejected, coordinatorAccepted
        case deadline, recorderRequest, recorderRejected, recorderAccepted
        case microphoneBegin, microphoneEnd, captureBegin, captureEnd
        case writerQueueBegin, writerQueueEnd, writerBegin, writerEnd, stopCompleted, stopFailed
    }
    let id = UUID().uuidString
    let enabled: Bool
    private var sequence = 0
    private let began = ProcessInfo.processInfo.systemUptime
    private let sink: (String) -> Void

    init(enabled: Bool = UserDefaults.standard.bool(forKey: "KlikStopDiagnostics"),
         sink: @escaping (String) -> Void = { DiagnosticsLogger.shared.write($0) }) {
        self.enabled = enabled
        self.sink = sink
    }

    // Only internally authored enum names and booleans/numbers reach the sink.
    func event(_ phase: Phase, source: Source? = nil, flag: Bool? = nil) {
        emit("phase=\(phase.rawValue)" + (source.map { " source=\($0.rawValue)" } ?? "")
             + (flag.map { " flag=\($0)" } ?? ""))
    }

    func mouse(up: Bool, stopHit: Bool, window: NSWindow) {
        emit("phase=windowMouse\(up ? "Up" : "Down") stopHit=\(stopHit) visible=\(window.isVisible) activeSpace=\(window.isOnActiveSpace) key=\(window.isKeyWindow) appActive=\(NSApp.isActive)")
    }

    private func emit(_ fields: String) {
        guard enabled else { return }
        sequence += 1
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - began) * 1000)
        sink("KlikStopTrace session=\(id) seq=\(sequence) ms=\(elapsed) \(fields)")
    }
}

@MainActor
final class RecordingControlWindow: NSWindow {
    var stopDiagnostics: RecordingStopDiagnostics?
    weak var diagnosticStopButton: NSButton?

    private func traceMouse(_ event: NSEvent) {
        guard stopDiagnostics?.enabled == true,
              event.type == .leftMouseDown || event.type == .leftMouseUp else { return }
        let hit = diagnosticStopButton.map {
            $0.bounds.contains($0.convert(event.locationInWindow, from: nil))
        } ?? false
        stopDiagnostics?.mouse(up: event.type == .leftMouseUp, stopHit: hit, window: self)
    }

    override func sendEvent(_ event: NSEvent) {
        traceMouse(event)
        super.sendEvent(event)
    }

    // Native NSButton tracking consumes mouse-up via nextEvent, not sendEvent.
    // Observe only dequeued releases for this window; never consume extra events.
    override func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?,
                            inMode mode: RunLoop.Mode, dequeue deqFlag: Bool) -> NSEvent? {
        let event = super.nextEvent(matching: mask, until: expiration, inMode: mode, dequeue: deqFlag)
        if deqFlag, let event, event.type == .leftMouseUp, event.windowNumber == windowNumber {
            traceMouse(event)
        }
        return event
    }
}

@MainActor
final class RecordingStopButton: NSButton {
    var stopDiagnostics: RecordingStopDiagnostics?
    var actionFired = false

    override func mouseDown(with event: NSEvent) {
        actionFired = false
        stopDiagnostics?.event(.trackingBegin, flag: isEnabled)
        defer { stopDiagnostics?.event(.trackingEnd, flag: actionFired) }
        super.mouseDown(with: event)
    }
}
