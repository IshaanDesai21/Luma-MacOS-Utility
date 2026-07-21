import Foundation
import Observation

/// Unified now-playing feed for the island. Self-contained: it polls Spotify and
/// Apple Music directly and shows whichever is actually playing, so it never
/// depends on another service's timing and always reflects reality right after
/// launch. Exposes the same track + controls surface regardless of the player.
@MainActor
@Observable
final class NowPlayingService {
    enum Source { case spotify, music, none }

    private(set) var track: Track?
    private(set) var source: Source = .none

    @ObservationIgnored private let spotify = SpotifyBridge()
    @ObservationIgnored private let music = MusicBridge()
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    func startMonitoring(interval: Duration = .seconds(1)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func refresh() async {
        // Query both players concurrently so a slow AppleScript can't stall the
        // other, then pick a winner.
        async let spotifyTrack = spotify.fetch()
        async let musicTrack = music.fetch()
        let candidates: [(Source, Track?)] = [(.spotify, await spotifyTrack), (.music, await musicTrack)]

        // Prefer whatever is actively playing; otherwise show any loaded track.
        if let playing = candidates.first(where: { $0.1?.isPlaying == true }) {
            track = playing.1
            source = playing.0
        } else if let paused = candidates.first(where: { $0.1 != nil }) {
            track = paused.1
            source = paused.0
        } else {
            track = nil
            source = .none
        }
    }

    // MARK: - Controls (routed to whichever player is active)

    func playPause() { command("playpause"); refreshSoon() }
    func nextTrack() { command("next track"); refreshSoon() }
    func previousTrack() { command("previous track"); refreshSoon() }

    func seek(to position: TimeInterval) {
        command("set player position to \(String(format: "%.2f", position))")
        if var current = track {          // optimistic update so the bar responds instantly
            current.position = position
            track = current
        }
        refreshSoon()
    }

    private func command(_ command: String) {
        switch source {
        case .spotify: spotify.command(command)
        case .music: music.command(command)
        case .none: break
        }
    }

    private func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await self?.refresh()
        }
    }
}

/// Apple Music AppleScript bridge, mirroring ``SpotifyBridge``: runs on its own
/// serial queue so polling never blocks the main thread.
final class MusicBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.luma.music.applescript", qos: .utility)
    private var query: NSAppleScript?

    func fetch() async -> Track? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                continuation.resume(returning: self?.run())
            }
        }
    }

    func command(_ command: String) {
        queue.async {
            let source = "tell application \"Music\" to \(command)"
            guard let script = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }

    // MARK: - Queue-confined work

    private func run() -> Track? {
        if query == nil { query = NSAppleScript(source: Self.querySource) }
        guard let query else { return nil }
        var error: NSDictionary?
        let descriptor = query.executeAndReturnError(&error)
        if error != nil { return nil }
        return Self.parse(descriptor.stringValue)
    }

    private static func parse(_ raw: String?) -> Track? {
        guard let raw, !raw.isEmpty else { return nil }
        let fields = raw.components(separatedBy: "\n")
        guard fields.count >= 6 else { return nil }

        let duration = Double(fields[3].trimmingCharacters(in: .whitespaces)) ?? 0
        let position = Double(fields[4].trimmingCharacters(in: .whitespaces)) ?? 0
        let state = fields[5].trimmingCharacters(in: .whitespaces)

        return Track(
            title: fields[0],
            artist: fields[1],
            album: fields[2],
            artworkURL: nil,               // Music.app exposes no artwork URL via scripting
            duration: duration,            // seconds (unlike Spotify's milliseconds)
            position: position,
            isPlaying: state == "playing"
        )
    }

    private static let querySource = """
    set output to ""
    tell application "System Events"
        set musicRunning to (exists (application processes whose name is "Music"))
    end tell
    if musicRunning then
        tell application "Music"
            set playerStateText to (player state as text)
            if playerStateText is "playing" or playerStateText is "paused" then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to (duration of current track) as text
                set trackPosition to (player position) as text
                set output to trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & trackDuration & linefeed & trackPosition & linefeed & playerStateText
            end if
        end tell
    end if
    return output
    """
}
