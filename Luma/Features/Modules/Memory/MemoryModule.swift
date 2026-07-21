import SwiftUI
import AppKit

final class MemoryModule: ModuleObject, Module {
    let id = "memory"
    let name = "Memory"
    let icon = "memorychip"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(services.monitor))
    }

    func menuBarPopover() -> AnyView? {
        AnyView(Popover(services.monitor))
    }

    private struct Chip: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            MenuBarChip(systemImage: nil, text: "RAM \(Int((monitor.memoryUsedFraction * 100).rounded()))%")
        }
    }

    private struct Popover: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.1f GB of %.0f GB", monitor.memoryUsedGB, monitor.memoryTotalGB))
                    .font(.system(size: 13, weight: .medium))
                ProgressView(value: monitor.memoryUsedFraction)
                    .frame(width: 180)
                Text(String(format: "Swap used  %.2f GB", monitor.swapUsedGB))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
