import SwiftUI
import AppKit

final class KeyboardModule: ModuleObject, Module {
    let id = "keyboard"
    let name = "Keyboard"
    let icon = "keyboard"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(source: services.inputSource))
    }

    func menuBarPopover() -> AnyView? {
        AnyView(Popover(source: services.inputSource))
    }

    private struct Chip: View {
        let source: InputSourceController
        var body: some View {
            MenuBarChip(systemImage: "keyboard", text: source.abbreviation)
        }
    }

    private struct Popover: View {
        let source: InputSourceController
        var body: some View {
            HStack(spacing: 10) {
                Text(source.name).font(.system(size: 13))
                Spacer(minLength: 8)
                Button("Switch") { source.cycle() }
            }
            .frame(minWidth: 200)
        }
    }
}
