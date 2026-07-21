import Foundation
import Observation

/// Observes Spotify playback and exposes playback controls.
///
/// AppleScript runs on ``SpotifyBridge``'s background queue; this type only
/// publishes results on the main actor.
@MainActor
@Observable
final class SpotifyService {
    private(set) var track: Track?

    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private let bridge = SpotifyBridge()

    func startMonitoring(interval: Duration = .seconds(1)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.track = await self.bridge.fetch()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Controls

    func playPause() { send("playpause") }
    func nextTrack() { send("next track") }
    func previousTrack() { send("previous track") }

    /// Seeks the current track to `position` seconds.
    func seek(to position: TimeInterval) {
        bridge.command("set player position to \(String(format: "%.2f", position))")
        if var current = track {         // optimistic update so the bar responds instantly
            current.position = position
            track = current
        }
        refreshSoon()
    }

    private func send(_ command: String) {
        bridge.command(command)
        refreshSoon()
    }

    private func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            self.track = await self.bridge.fetch()
        }
    }
}
