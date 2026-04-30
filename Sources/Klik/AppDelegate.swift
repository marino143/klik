import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var captureCoordinator: CaptureCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        captureCoordinator = CaptureCoordinator()
        hotkeyManager = HotkeyManager()
        registerHotkeys()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Klik")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(makeMenuItem("Capture Region", key: "2", action: #selector(captureRegion)))
        menu.addItem(makeMenuItem("Capture Full Screen", key: "3", action: #selector(captureFullScreen)))
        menu.addItem(makeMenuItem("Capture Window", key: "4", action: #selector(captureWindow)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem("Record Video (Full Screen)", key: "5", action: #selector(toggleVideo)))
        let regionItem = NSMenuItem(title: "Record Video (Region)", action: #selector(toggleVideoRegion), keyEquivalent: "")
        regionItem.target = self
        menu.addItem(regionItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem("Settings…", key: ",", action: #selector(openSettings)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem("Quit Klik", key: "q", action: #selector(quit)))
        statusItem.menu = menu
    }

    private func makeMenuItem(_ title: String, key: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        return item
    }

    private func registerHotkeys() {
        hotkeyManager.register(keyCode: UInt32(kVK_ANSI_2), modifiers: [.command, .shift]) { [weak self] in
            self?.captureRegion()
        }
        hotkeyManager.register(keyCode: UInt32(kVK_ANSI_3), modifiers: [.command, .shift]) { [weak self] in
            self?.captureFullScreen()
        }
        hotkeyManager.register(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .shift]) { [weak self] in
            self?.captureWindow()
        }
        hotkeyManager.register(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift]) { [weak self] in
            self?.toggleVideo()
        }
    }

    @objc private func captureRegion() {
        captureCoordinator.captureRegion()
    }

    @objc private func captureFullScreen() {
        captureCoordinator.captureFullScreen()
    }

    @objc private func captureWindow() {
        captureCoordinator.captureWindow()
    }

    @objc private func toggleVideo() {
        captureCoordinator.toggleVideoRecording()
    }

    @objc private func toggleVideoRegion() {
        captureCoordinator.toggleRegionVideoRecording()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
