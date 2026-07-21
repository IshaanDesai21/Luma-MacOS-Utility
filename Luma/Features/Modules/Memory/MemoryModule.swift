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
        AnyView(Popover(monitor: services.monitor))
    }

    // The detailed breakdown styles itself, so skip the generic titled chrome.
    var menuBarPopoverUsesChrome: Bool { false }

    private struct Chip: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            MenuBarChip(systemImage: nil, text: "RAM \(Int((monitor.memoryUsedFraction * 100).rounded()))%")
        }
    }

    private struct Popover: View {
        let monitor: SystemMonitor
        @State private var reader = ProcessMemoryReader()

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                processList
            }
            .padding(16)
            .frame(width: 300)
            .task {
                await reader.reload()
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Memory", systemImage: "memorychip")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(Int((monitor.memoryUsedFraction * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                // Segmented usage bar.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(usageColor)
                            .frame(width: geo.size.width * monitor.memoryUsedFraction)
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(String(format: "%.1f GB of %.0f GB used", monitor.memoryUsedGB, monitor.memoryTotalGB))
                    Spacer()
                    Text(String(format: "Swap %.1f GB", monitor.swapUsedGB))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }

        private var usageColor: Color {
            switch monitor.memoryUsedFraction {
            case ..<0.7: return .green
            case ..<0.88: return .orange
            default: return .red
            }
        }

        @ViewBuilder
        private var processList: some View {
            HStack {
                Text("Top processes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if reader.isLoading {
                    ProgressView().controlSize(.mini)
                }
            }

            let maxBytes = reader.processes.map(\.residentBytes).max() ?? 1
            VStack(spacing: 8) {
                ForEach(reader.processes) { process in
                    row(process, maxBytes: maxBytes)
                }
                if reader.processes.isEmpty && !reader.isLoading {
                    Text("No data available")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        private func row(_ process: ProcessMemoryReader.Process, maxBytes: Int64) -> some View {
            VStack(spacing: 3) {
                HStack {
                    Text(process.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Text(memoryText(process.megabytes))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(.tint)
                        .frame(width: geo.size.width * barFraction(process.residentBytes, maxBytes: maxBytes))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 4)
            }
        }

        private func barFraction(_ bytes: Int64, maxBytes: Int64) -> CGFloat {
            guard maxBytes > 0 else { return 0 }
            return CGFloat(bytes) / CGFloat(maxBytes)
        }

        private func memoryText(_ mb: Double) -> String {
            mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
        }
    }
}
