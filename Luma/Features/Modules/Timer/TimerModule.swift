import SwiftUI
import AppKit

final class TimerModule: ModuleObject, Module {
    let id = "timer"
    let name = "Timer"
    let icon = "timer"
    let supportedLocations: Set<ModuleLocation> = [.menuBar]

    func menuBarView() -> AnyView? {
        AnyView(Chip(services.timer))
    }

    func menuBarPopover() -> AnyView? {
        AnyView(Controls(timer: services.timer))
    }

    private struct Chip: View {
        let timer: TimerService
        init(_ timer: TimerService) { self.timer = timer }
        var body: some View {
            MenuBarChip(systemImage: timer.isRunning ? "timer" : "timer.circle", text: timer.formatted)
        }
    }

    private struct Controls: View {
        let timer: TimerService
        var body: some View {
            VStack(spacing: 12) {
                Text(timer.formatted)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 8) {
                    stepper("-1m") { timer.setDuration(timer.duration - 60) }
                    stepper("+1m") { timer.setDuration(timer.duration + 60) }
                }

                HStack(spacing: 8) {
                    Button(timer.isRunning ? "Pause" : "Start") { timer.toggle() }
                        .buttonStyle(.borderedProminent)
                    Button("Reset") { timer.reset() }
                        .buttonStyle(.bordered)
                }
            }
            .frame(width: 200)
        }

        private func stepper(_ title: String, action: @escaping () -> Void) -> some View {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .disabled(timer.isRunning)
        }
    }
}
