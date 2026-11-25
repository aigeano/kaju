// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import Carbon
import KajuCore

/// System-wide hotkey through Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission.
final class HotkeyManager {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, user in
            guard let user else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(user).takeUnretainedValue()
            DispatchQueue.main.async { manager.action() }
            return noErr
        }, 1, &spec, me, &handlerRef)
    }

    /// Register a hotkey; returns false if it is invalid or held by another app.
    func register(_ hotkey: Hotkey) -> Bool {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        guard let code = hotkey.keyCode else { return false }
        var mods: UInt32 = 0
        if hotkey.modifiers.contains(.cmd) { mods |= UInt32(cmdKey) }
        if hotkey.modifiers.contains(.ctrl) { mods |= UInt32(controlKey) }
        if hotkey.modifiers.contains(.opt) { mods |= UInt32(optionKey) }
        if hotkey.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        let id = EventHotKeyID(signature: OSType(0x6B616A75), id: 1)  // 'kaju'
        return RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }
}
