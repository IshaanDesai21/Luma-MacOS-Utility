import SwiftUI
import AppKit

final class DownloadsModule: ModuleObject, Module {
    let id = "downloads"
    let name = "Downloads"
    let icon = "arrow.down.circle"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(downloads: services.downloads))
    }

    func menuBarPopover() -> AnyView? {
        AnyView(Popover(downloads: services.downloads))
    }

    private struct Chip: View {
        let downloads: DownloadsService
        var body: some View {
            MenuBarChip(
                systemImage: downloads.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle",
                text: downloads.activeCount > 0 ? "\(downloads.activeCount)" : ""
            )
        }
    }

    private struct Popover: View {
        let downloads: DownloadsService
        var body: some View {
            VStack(spacing: 6) {
                if downloads.items.isEmpty {
                    Text("No recent downloads")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(8)
                } else {
                    ForEach(downloads.items) { item in
                        row(item)
                    }
                }
            }
            .frame(width: 260)
        }

        private func row(_ item: DownloadsService.Item) -> some View {
            HStack(spacing: 8) {
                Image(nsImage: downloads.icon(for: item))
                    .resizable().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.system(size: 12)).lineLimit(1)
                    HStack(spacing: 4) {
                        if item.inProgress {
                            ProgressView().controlSize(.mini)
                            Text("Downloading… \(downloads.formattedSize(item))")
                        } else {
                            Text(downloads.formattedSize(item))
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { downloads.reveal(item) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain).help("Reveal in Finder")
                Button { downloads.open(item) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain).help("Open")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
