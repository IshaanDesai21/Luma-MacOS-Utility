import SwiftUI
import AppKit

final class CalendarModule: ModuleObject, Module {
    let id = "calendar"
    let name = "Calendar"
    let icon = "calendar"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(services.monitor))
    }

    func menuBarPopover() -> AnyView? {
        AnyView(MonthCalendarView(style: .popover))
    }

    var menuBarPopoverUsesChrome: Bool { false }

    private struct Chip: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            MenuBarChip(systemImage: "calendar", text: monitor.date.formatted(.dateTime.weekday(.abbreviated).day()))
        }
    }

    private struct Popover: View {
        let monitor: SystemMonitor
        init(_ monitor: SystemMonitor) { self.monitor = monitor }
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(monitor.date.formatted(.dateTime.month(.wide).day()))
                    .font(.system(size: 17, weight: .semibold))
            }
        }
    }
}
