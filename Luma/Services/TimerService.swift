import Foundation
import Observation

/// A simple countdown timer shared by the Timer module across surfaces.
@MainActor
@Observable
final class TimerService {
    private(set) var remaining: TimeInterval = 0
    private(set) var duration: TimeInterval = 5 * 60
    private(set) var isRunning = false

    @ObservationIgnored private var task: Task<Void, Never>?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - remaining / duration, 0), 1)
    }

    var formatted: String {
        let value = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    func setDuration(_ seconds: TimeInterval) {
        duration = max(seconds, 1)
        if !isRunning { remaining = duration }
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        if remaining <= 0 { remaining = duration }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isRunning else { break }
                self.tick()
            }
        }
    }

    func pause() {
        isRunning = false
        task?.cancel()
        task = nil
    }

    func reset() {
        pause()
        remaining = duration
    }

    private func tick() {
        remaining = max(remaining - 1, 0)
        if remaining <= 0 { pause() }
    }
}
