import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private struct Hotkey {
        let id: UInt32
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var hotkeys: [UInt32: Hotkey] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {
        installHandler()
    }

    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        for hotkey in hotkeys.values {
            UnregisterEventHotKey(hotkey.ref)
        }
    }

    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1

        let hotkeyID = EventHotKeyID(signature: OSType(0x4B4C4B49), id: id)
        var hotkeyRef: EventHotKeyRef?

        let carbonModifiers = carbonModifierFlags(from: modifiers)
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let ref = hotkeyRef else {
            NSLog("Klik: hotkey registration failed (status: \(status))")
            return
        }

        hotkeys[id] = Hotkey(id: id, ref: ref, handler: handler)
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef = eventRef, let userData = userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                guard status == noErr else { return status }
                if let hotkey = manager.hotkeys[hotkeyID.id] {
                    DispatchQueue.main.async {
                        hotkey.handler()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }

    private func carbonModifierFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
}
