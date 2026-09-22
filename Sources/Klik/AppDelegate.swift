import AppKit
import Carbon.HIToolbox
#if !APP_STORE
import Sparkle
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var captureCoordinator: CaptureCoordinator!
    #if !APP_STORE
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticsLogger.shared.start()
        setupStatusItem()
        captureCoordinator = CaptureCoordinator()
        captureCoordinator.restoreInterruptedRecordings()
        hotkeyManager = HotkeyManager()
        registerHotkeys()
        #if APP_STORE
        offerSaveFolderAccessIfNeeded()
        #endif
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
        #if !APP_STORE
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        #endif
        #if !APP_STORE
        let diagnosticsItem = NSMenuItem(title: "Export Diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)
        menu.addItem(NSMenuItem.separator())
        let coffeeItem = NSMenuItem(title: "Buy me a coffee ☕", action: #selector(openBuyMeACoffee), keyEquivalent: "")
        coffeeItem.target = self
        menu.addItem(coffeeItem)
        #endif
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

    #if !APP_STORE
    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func exportDiagnostics() {
        DiagnosticsExporter.export()
    }

    @objc private func openBuyMeACoffee() {
        if let url = URL(string: "https://buymeacoffee.com/marino143") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif

    #if APP_STORE
    private func offerSaveFolderAccessIfNeeded() {
        guard Storage.shared.needsSaveDirectorySelection,
              !UserDefaults.standard.bool(forKey: "Klik.didOfferSaveDirectory") else { return }
        UserDefaults.standard.set(true, forKey: "Klik.didOfferSaveDirectory")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Choose where Klik saves captures"
            alert.informativeText = "The Mac App Store version can only save outside its private container after you choose a folder. You can change it later in Settings."
            alert.addButton(withTitle: "Choose Folder")
            alert.addButton(withTitle: "Not Now")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            _ = Storage.shared.chooseSaveDirectory()
        }
    }
    #endif

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
