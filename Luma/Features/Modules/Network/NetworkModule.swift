import SwiftUI
import AppKit

final class NetworkModule: ModuleObject, Module {
    let id = "network"
    let name = "Network"
    let icon = "network"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(services.monitor))
    }

    func menuBarPopover() -> AnyView? {
        AnyView(Popover(services.monitor))
    }

    static func rate(_ kbps: Double) -> String {
        if kbps >= 1024 { return String(format: "%.1f MB/s", kbps / 1024) }
        return String(format: "%.0f KB/s", kbps)
    }

    private struct Chip: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            HStack(spacing: 6) {
                MenuBarChip(systemImage: "arrow.down", text: NetworkModule.rate(monitor.networkDownKBps))
                MenuBarChip(systemImage: "arrow.up", text: NetworkModule.rate(monitor.networkUpKBps))
            }
        }
    }

    private struct Popover: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label("Download  \(NetworkModule.rate(monitor.networkDownKBps))", systemImage: "arrow.down.circle")
                Label("Upload  \(NetworkModule.rate(monitor.networkUpKBps))", systemImage: "arrow.up.circle")
            }
            .font(.system(size: 13))
        }
    }
}
