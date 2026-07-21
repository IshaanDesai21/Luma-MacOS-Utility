import SwiftUI
import AppKit

final class ClockModule: ModuleObject, Module {
    let id = "clock"
    let name = "Clock"
    let icon = "clock"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Label(services.monitor))
    }

    private struct Label: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            MenuBarChip(text: monitor.date.formatted(date: .omitted, time: .shortened))
        }
    }
}
