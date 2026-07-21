import SwiftUI
import AppKit

final class FileShelfModule: ModuleObject, Module {
    let id = "fileShelf"
    let name = "File Shelf"
    let icon = "tray.full"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(shelf: services.shelf))
    }

    func menuBarPopover() -> AnyView? {
        AnyView(ShelfView(shelf: services.shelf))
    }

    private struct Chip: View {
        let shelf: FileShelf
        var body: some View {
            MenuBarChip(
                systemImage: shelf.items.isEmpty ? "tray" : "tray.full",
                text: shelf.items.isEmpty ? "" : "\(shelf.items.count)"
            )
        }
    }

    private struct ShelfView: View {
        let shelf: FileShelf

        var body: some View {
            VStack(spacing: 8) {
                ForEach(shelf.items) { item in
                    row(item)
                }
                dropZone
                if !shelf.items.isEmpty {
                    Button("Clear All", role: .destructive) { shelf.clear() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
            }
            .frame(width: 250)
        }

        private func row(_ item: FileShelf.Item) -> some View {
            HStack(spacing: 8) {
                Image(nsImage: shelf.icon(for: item))
                    .resizable().frame(width: 20, height: 20)
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button { shelf.open(item) } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .help("Open")
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .draggable(item.url)
        }

        private var dropZone: some View {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(.secondary)
                .frame(height: 52)
                .overlay {
                    Label("Drop files to hold", systemImage: "tray.and.arrow.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .dropDestination(for: URL.self) { urls, _ in
                    shelf.add(urls: urls)
                    return true
                }
        }
    }
}
