import AppKit
import Foundation
import Observation

/// Unified now-playing feed for the island. Detection, most-reliable first:
///  1. `ungive/mediaremote-adapter` (if bundled) — system-wide, any player.
///  2. Distributed notifications from Spotify / Apple Music — instant and need
///     no permission (great for display even when Automation is denied).
///  3. AppleScript polling — authoritative position + playback control.
/// Position is interpolated between updates so the seek bar moves smoothly.
@MainActor
@Observable
final class NowPlayingService {
    enum Source: Equatable { case adapter, spotify, music, none }

    private(set) var track: Track?
    private(set) var source: Source = .none

    @ObservationIgnored private let adapter = MediaRemoteAdapterService()
    @ObservationIgnored private let spotify = SpotifyBridge()
    @ObservationIgnored private let music = MusicBridge()

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    // Elapsed-time anchor for smooth interpolation.
    @ObservationIgnored private var anchorElapsed: TimeInterval = 0
    @ObservationIgnored private var anchorAt: Date = Date()

    private static let spotifyBundleID = "com.spotify.client"

    var systemFeedAvailable: Bool { adapter.isAvailable }

    // MARK: - Lifecycle

    func startMonitoring(interval: Duration = .seconds(1)) {
        // 1. System-wide adapter (if the helper files are bundled).
        if adapter.isAvailable {
            adapter.start { [weak self] np in self?.applyAdapter(np) }
        }
        // 2. Instant, permission-free change notifications.
        registerNotifications()
        // 3. AppleScript polling (fallback + accurate position when permitted).
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isAdapterAuthoritative { await self.refreshViaScript() }
                try? await Task.sleep(for: interval)
            }
        }
        // Smooth progress between updates.
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.tickInterpolatedPosition()
            }
        }
    }

    func stopMonitoring() {
        adapter.stop()
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        pollTask?.cancel(); pollTask = nil
        tickTask?.cancel(); tickTask = nil
    }

    private var isAdapterAuthoritative: Bool {
        adapter.isAvailable && source == .adapter
    }

    // MARK: - Adapter path

    private func applyAdapter(_ np: MediaRemoteAdapterService.NowPlaying?) {
        guard let np, !np.title.isEmpty else {
            if source == .adapter { clear() }
            return
        }
        track = Track(
            title: np.title,
            artist: np.artist,
            album: np.album,
            artworkData: np.artworkData,
            duration: np.duration,
            position: np.elapsed,
            isPlaying: np.isPlaying
        )
        source = .adapter
        anchor(np.elapsed)
    }

    // MARK: - Distributed notifications (permission-free)

    private func registerNotifications() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.ingestNotification(note.userInfo, source: .spotify) }
        })
        for name in ["com.apple.Music.playerInfo", "com.apple.iTunes.playerInfo"] {
            observers.append(dnc.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated { self?.ingestNotification(note.userInfo, source: .music) }
            })
        }
    }

    private func ingestNotification(_ info: [AnyHashable: Any]?, source newSource: Source) {
        // The adapter, when present, is the authority — ignore notifications.
        guard !isAdapterAuthoritative, let info else { return }
        let state = (info["Player State"] as? String) ?? ""
        guard let name = info["Name"] as? String, !name.isEmpty, state != "Stopped" else {
            if source == newSource { clear() }
            return
        }
        let durationMs = (info["Duration"] as? Double) ?? (info["Total Time"] as? Double) ?? 0
        let artworkURL = (info["Artwork URL"] as? String).flatMap(URL.init(string:))
        track = Track(
            title: name,
            artist: (info["Artist"] as? String) ?? "",
            album: (info["Album"] as? String) ?? "",
            artworkURL: artworkURL,
            duration: durationMs / 1000,
            position: currentInterpolatedPosition() ?? 0,
            isPlaying: state == "Playing"
        )
        source = newSource
        anchor(track?.position ?? 0)
        // Ask AppleScript for the exact position/artwork if we're allowed.
        Task { await refreshViaScript() }
    }

    // MARK: - AppleScript path

    private func refreshViaScript() async {
        async let spotifyTrack = spotify.fetch()
        async let musicTrack = music.fetch()
        let s = await spotifyTrack
        let m = await musicTrack
        let candidates: [(Source, Track?)] = [(.spotify, s), (.music, m)]

        if let playing = candidates.first(where: { $0.1?.isPlaying == true }) {
            set(playing.1, source: playing.0)
        } else if let paused = candidates.first(where: { $0.1 != nil }) {
            set(paused.1, source: paused.0)
        } else if source == .spotify || source == .music {
            // Only clear if we were the AppleScript owner (a notification may
            // still hold a valid track that AppleScript can't read without perm).
            if track == nil { clear() }
        }
    }

    private func set(_ newTrack: Track?, source newSource: Source) {
        guard let newTrack else { return }
        track = newTrack
        source = newSource
        anchor(newTrack.position)
    }

    private func clear() {
        track = nil
        source = .none
    }

    // MARK: - Position interpolation

    private func anchor(_ elapsed: TimeInterval) {
        anchorElapsed = elapsed
        anchorAt = Date()
    }

    private func currentInterpolatedPosition() -> TimeInterval? {
        guard let track else { return nil }
        guard track.isPlaying else { return track.position }
        return anchorElapsed + Date().timeIntervalSince(anchorAt)
    }

    private func tickInterpolatedPosition() {
        guard var t = track, t.isPlaying, t.duration > 0 else { return }
        let pos = min(anchorElapsed + Date().timeIntervalSince(anchorAt), t.duration)
        t.position = pos
        track = t
    }

    // MARK: - Controls (routed to whichever source is active)

    func playPause() {
        switch source {
        case .adapter: adapter.togglePlayPause()
        case .spotify: spotify.command("playpause")
        case .music: music.command("playpause")
        case .none: launchSpotify(); return
        }
        anchor(currentInterpolatedPosition() ?? 0)
        refreshSoon()
    }

    func nextTrack() {
        switch source {
        case .adapter: adapter.next()
        case .spotify: spotify.command("next track")
        case .music: music.command("next track")
        case .none: return
        }
        refreshSoon()
    }

    func previousTrack() {
        switch source {
        case .adapter: adapter.previous()
        case .spotify: spotify.command("previous track")
        case .music: music.command("previous track")
        case .none: return
        }
        refreshSoon()
    }

    func seek(to position: TimeInterval) {
        switch source {
        case .adapter: adapter.seek(to: position)
        case .spotify: spotify.command("set player position to \(String(format: "%.2f", position))")
        case .music: music.command("set player position to \(String(format: "%.2f", position))")
        case .none: return
        }
        if var current = track { current.position = position; track = current }
        anchor(position)
    }

    /// The app icon for the current source, for the little badge on the artwork.
    func sourceBadge() -> NSImage? {
        switch source {
        case .spotify: return Self.appIcon(bundleID: Self.spotifyBundleID)
        case .music: return Self.appIcon(bundleID: "com.apple.Music")
        case .adapter:
            if let id = adapter.current?.bundleIdentifier { return Self.appIcon(bundleID: id) }
            return nil
        case .none: return nil
        }
    }

    private static func appIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func launchSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyBundleID) else {
            if let web = URL(string: "https://open.spotify.com") { NSWorkspace.shared.open(web) }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !self.isAdapterAuthoritative else { return }
            await self.refreshViaScript()
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
            duration: duration,
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
