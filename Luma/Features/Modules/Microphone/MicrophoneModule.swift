import SwiftUI
import AppKit

final class MicrophoneModule: ModuleObject, Module {
    let id = "microphone"
    let name = "Microphone"
    let icon = "mic"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(services.microphone))
    }

    // Already icon-only; the compact form is identical (stateful mute glyph).
    func menuBarView(compact: Bool) -> AnyView? {
        AnyView(Chip(services.microphone))
    }

    // Clicking the menu-bar mic toggles directly — no popover.
    func menuBarAction() -> (() -> Void)? {
        { [weak self] in self?.toggle() }
    }

    private func toggle() {
        let muted = services.microphone.toggle()
        services.hud.show(
            symbol: muted ? "mic.slash.fill" : "mic.fill",
            title: muted ? "Mic Muted" : "Mic Unmuted",
            animationSpeed: services.settings.animationSpeed
        )
    }

    private struct Chip: View {
        let microphone: MicrophoneController
        init(_ microphone: MicrophoneController) { self.microphone = microphone }
        var body: some View {
            MenuBarChip(systemImage: microphone.isMuted ? "mic.slash.fill" : "mic.fill", text: "")
        }
    }

}
