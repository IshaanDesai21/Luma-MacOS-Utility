import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon (no Accessibility permission needed)
/// and dispatches them to per-id handlers.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false
    private let signature: OSType = 0x4C554D41 // 'LUMA'

    private init() {}

    func register(id: UInt32, shortcut: GlobalShortcut?, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        unregister(id: id)
        guard let shortcut else { return }

        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr { refs[id] = ref }
    }

    func unregister(id: UInt32) {
        if let ref = refs[id] {
            UnregisterEventHotKey(ref)
            refs[id] = nil
        }
        handlers[id] = nil
    }

    fileprivate func handle(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &spec, nil, nil)
    }
}

/// Top-level C callback (no captures) so it converts to an `EventHandlerUPP`.
private func hotkeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotkeyCenter.shared.handle(id) }
    }
    return noErr
}
