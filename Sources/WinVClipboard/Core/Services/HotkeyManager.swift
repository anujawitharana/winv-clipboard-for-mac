import Foundation
import Carbon
import AppKit

public final class HotkeyManager: @unchecked Sendable {
    public static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x57494E56 // 'WINV'
    private let hotKeyID: UInt32 = 1

    private let userDefaultsKey = "WinVCustomHotkey"
    private var currentCombo: KeyCombo = KeyCombo.defaultShortcut
    public var onHotKeyTriggered: (@MainActor () -> Void)?

    private init() {
        loadSavedShortcut()
    }

    public var activeShortcut: KeyCombo {
        return currentCombo
    }

    public func start() {
        installCarbonEventHandler()
        _ = register(combo: currentCombo)
    }

    public func updateShortcut(to newCombo: KeyCombo) -> Bool {
        unregisterCurrentHotKey()
        currentCombo = newCombo
        saveShortcut(newCombo)
        return register(combo: newCombo)
    }

    public func resetToDefault() -> Bool {
        return updateShortcut(to: KeyCombo.defaultShortcut)
    }

    private func register(combo: KeyCombo) -> Bool {
        let hotKeyIDStruct = EventHotKeyID(signature: signature, id: hotKeyID)
        var newRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyIDStruct,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        if status == noErr {
            self.hotKeyRef = newRef
            return true
        } else {
            NSLog("Failed to register Carbon hotkey with status: %d", status)
            return false
        }
    }

    private func unregisterCurrentHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerBlock: EventHandlerUPP = { (_, theEvent, userData) -> OSStatus in
            guard let event = theEvent, let userData = userData else { return OSStatus(eventNotHandledErr) }

            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )

            if status == noErr {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if hkID.signature == manager.signature && hkID.id == manager.hotKeyID {
                    DispatchQueue.main.async {
                        manager.onHotKeyTriggered?()
                    }
                    return noErr
                }
            }
            return OSStatus(eventNotHandledErr)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handlerBlock, 1, &eventType, selfPtr, &eventHandlerRef)
    }

    private func loadSavedShortcut() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            self.currentCombo = saved
        } else {
            self.currentCombo = KeyCombo.defaultShortcut
        }
    }

    private func saveShortcut(_ combo: KeyCombo) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
