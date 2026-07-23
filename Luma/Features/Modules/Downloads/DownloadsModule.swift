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

    // The popover styles itself (header + Clear button), so skip generic chrome.
    var menuBarPopoverUsesChrome: Bool { false }

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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloads")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if !downloads.items.isEmpty {
                        Button("Clear") { downloads.clearList() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tint)
                    }
                }

                if downloads.items.isEmpty {
                    Text("No recent downloads")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(downloads.items) { item in
                            row(item)
                        }
                    }
                    Text("Tip: drag a file out to move or copy it.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(width: 280)
        }

        private func row(_ item: DownloadsService.Item) -> some View {
            HStack(spacing: 8) {
                Image(nsImage: downloads.icon(for: item))
                    .resizable().frame(width: 26, height: 26)
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
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // Drag the actual file out of the popover (unless still downloading).
            .draggable(item.url) {
                HStack(spacing: 6) {
                    Image(nsImage: downloads.icon(for: item)).resizable().frame(width: 20, height: 20)
                    Text(item.name).font(.system(size: 11)).lineLimit(1)
                }
                .padding(6)
            }
        }
    }
}
