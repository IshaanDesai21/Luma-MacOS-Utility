import AppKit
import Foundation
import Observation

/// Unified now-playing feed for the island. Polls Spotify and Apple Music via
/// AppleScript (reliable, with artwork + full controls) and, when available,
/// the system-wide MediaRemote feed (browser video etc.). Shows whichever is
/// actually playing and routes controls to that source.
@MainActor
@Observable
final class NowPlayingService {
    enum Source: Equatable { case spotify, music, system, none }

    private(set) var track: Track?
    private(set) var source: Source = .none

    @ObservationIgnored private let spotify = SpotifyBridge()
    @ObservationIgnored private let music = MusicBridge()
    @ObservationIgnored private let system = MediaRemoteBridge()
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    private static let spotifyBundleID = "com.spotify.client"

    /// True when the system feed is usable on this OS (macOS 14.0-15.3).
    var systemFeedAvailable: Bool { system.isAvailable }

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
        // Query every source concurrently so a slow one can't stall the others.
        async let spotifyTrack = spotify.fetch()
        async let musicTrack = music.fetch()
        async let systemInfo = system.fetch()

        let s = await spotifyTrack
        let m = await musicTrack
        let sys = (await systemInfo).map(Self.track(from:))

        // App players (Spotify/Music) win when playing — better controls and
        // artwork. The system feed covers everything else (browser video).
        let candidates: [(Source, Track?)] = [(.spotify, s), (.music, m), (.system, sys)]

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

    private static func track(from info: MediaRemoteBridge.Info) -> Track {
        Track(
            title: info.title,
            artist: info.artist,
            album: info.album,
            artworkData: info.artworkData,
            duration: info.duration,
            position: info.elapsed,
            isPlaying: info.isPlaying
        )
    }

    // MARK: - Controls (routed to whichever player is active)

    func playPause() {
        switch source {
        case .spotify: spotify.command("playpause")
        case .music: music.command("playpause")
        case .system: system.togglePlayPause()
        case .none:
            // Nothing is playing: open Spotify so the play button always does
            // something sensible.
            launchSpotify()
            return
        }
        refreshSoon()
    }

    func nextTrack() {
        switch source {
        case .spotify: spotify.command("next track")
        case .music: music.command("next track")
        case .system: system.next()
        case .none: return
        }
        refreshSoon()
    }

    func previousTrack() {
        switch source {
        case .spotify: spotify.command("previous track")
        case .music: music.command("previous track")
        case .system: system.previous()
        case .none: return
        }
        refreshSoon()
    }

    func seek(to position: TimeInterval) {
        switch source {
        case .spotify: spotify.command("set player position to \(String(format: "%.2f", position))")
        case .music: music.command("set player position to \(String(format: "%.2f", position))")
        case .system, .none: return   // MediaRemote seek is unreliable; skip.
        }
        if var current = track {          // optimistic update so the bar responds instantly
            current.position = position
            track = current
        }
        refreshSoon()
    }

    /// The app icon for the current source, for the little badge on the artwork.
    func sourceBadge() -> NSImage? {
        switch source {
        case .spotify: return Self.appIcon(bundleID: Self.spotifyBundleID)
        case .music: return Self.appIcon(bundleID: "com.apple.Music")
        case .system, .none: return nil
        }
    }

    private static func appIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func launchSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyBundleID) else {
            // Spotify isn't installed; send people to get it.
            if let web = URL(string: "https://open.spotify.com") { NSWorkspace.shared.open(web) }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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
