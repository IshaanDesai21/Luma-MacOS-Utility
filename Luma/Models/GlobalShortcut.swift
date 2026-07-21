import AppKit
import Carbon.HIToolbox

/// A user-recorded global keyboard shortcut (stored with Carbon modifier flags).
struct GlobalShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        guard carbon != 0 else { return nil } // require at least one modifier

        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        text += (event.charactersIgnoringModifiers ?? "").uppercased()

        self.keyCode = UInt32(event.keyCode)
        self.modifiers = carbon
        self.display = text
    }
}
