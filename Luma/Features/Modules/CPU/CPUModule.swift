import SwiftUI
import AppKit

final class CPUModule: ModuleObject, Module {
    let id = "cpu"
    let name = "CPU"
    let icon = "cpu"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(services.monitor))
    }

    static func percent(_ monitor: SystemMonitor) -> String {
        "\(Int((monitor.cpuUsage * 100).rounded()))%"
    }

    private struct Chip: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            MenuBarChip(systemImage: nil, text: "CPU \(CPUModule.percent(monitor))")
        }
    }
}
