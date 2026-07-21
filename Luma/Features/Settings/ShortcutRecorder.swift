import SwiftUI
import AppKit

/// A control that records a global keyboard shortcut from the next key press.
struct ShortcutRecorder: View {
    @Binding var shortcut: GlobalShortcut?

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(recording ? "Press keys…" : (shortcut?.display ?? "Record"))
                    .frame(minWidth: 84)
                    .monospacedDigit()
            }
            if shortcut != nil && !recording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // escape cancels
                stop()
                return nil
            }
            if let recorded = GlobalShortcut(event: event) {
                shortcut = recorded
            }
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
