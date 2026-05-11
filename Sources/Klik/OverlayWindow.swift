import AppKit

/// Borderless full-screen overlay window that can become key — required so
/// keyboard events (e.g. Escape to cancel) reach the contentView.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
