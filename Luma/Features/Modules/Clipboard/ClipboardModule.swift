import SwiftUI
import AppKit

final class ClipboardModule: ModuleObject, Module {
    let id = "clipboard"
    let name = "Clipboard"
    let icon = "doc.on.clipboard"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(MenuBarChip(systemImage: "doc.on.clipboard", text: ""))
    }

    func menuBarPopover() -> AnyView? {
        AnyView(Popover(clipboard: services.clipboard))
    }

    private struct Popover: View {
        let clipboard: ClipboardService
        var body: some View {
            VStack(spacing: 6) {
                if clipboard.items.isEmpty {
                    Text("Clipboard history is empty")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(8)
                } else {
                    ForEach(clipboard.items.prefix(12)) { item in
                        Button { clipboard.copy(item) } label: {
                            Text(item.text)
                                .font(.system(size: 12))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy")
                    }
                    Button("Clear History", role: .destructive) { clipboard.clear() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
            }
            .frame(width: 260)
        }
    }
}
