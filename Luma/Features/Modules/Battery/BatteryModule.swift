import SwiftUI
import AppKit

final class BatteryModule: ModuleObject, Module {
    let id = "battery"
    let name = "Battery"
    let icon = "battery.100"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(services.monitor))
    }

    func menuBarView(compact: Bool) -> AnyView? {
        compact ? AnyView(CompactChip(services.monitor)) : menuBarView()
    }

    private struct CompactChip: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            MenuBarChip(systemImage: BatteryModule.symbol(monitor), text: "")
        }
    }

    static func percentText(_ monitor: SystemMonitor) -> String {
        guard monitor.hasBattery else { return "—" }
        return "\(Int((monitor.batteryLevel * 100).rounded()))%"
    }

    static func symbol(_ monitor: SystemMonitor) -> String {
        if monitor.batteryCharging { return "battery.100.bolt" }
        switch monitor.batteryLevel {
        case ..<0.15: return "battery.0"
        case ..<0.45: return "battery.25"
        case ..<0.75: return "battery.50"
        default: return "battery.100"
        }
    }

    private struct Chip: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            MenuBarChip(systemImage: BatteryModule.symbol(monitor), text: BatteryModule.percentText(monitor))
        }
    }
}
