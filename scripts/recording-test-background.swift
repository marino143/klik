// Separate process: the recorder must not exclude the synthetic background.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSScreen.main!.frame, styleMask: .borderless, backing: .buffered, defer: false)
window.backgroundColor = NSColor(srgbRed: 0.15, green: 0.8, blue: 0.35, alpha: 1)
window.isOpaque = true
window.level = .floating
window.orderFrontRegardless()
Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in app.terminate(nil) }
app.run()
