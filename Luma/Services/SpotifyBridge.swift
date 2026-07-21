import Foundation

/// Runs Spotify AppleScript on a dedicated serial queue so polling and playback
/// commands never block the main thread (the previous main-thread execution was
/// the app's biggest source of UI lag).
final class SpotifyBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.luma.spotify.applescript", qos: .utility)
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
            let source = "tell application \"Spotify\" to \(command)"
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
        guard fields.count >= 7 else { return nil }

        let durationMilliseconds = Double(fields[3].trimmingCharacters(in: .whitespaces)) ?? 0
        let position = Double(fields[5].trimmingCharacters(in: .whitespaces)) ?? 0
        let state = fields[6].trimmingCharacters(in: .whitespaces)

        return Track(
            title: fields[0],
            artist: fields[1],
            album: fields[2],
            artworkURL: URL(string: fields[4].trimmingCharacters(in: .whitespaces)),
            duration: durationMilliseconds / 1000,
            position: position,
            isPlaying: state == "playing"
        )
    }

    private static let querySource = """
    set output to ""
    tell application "System Events"
        set spotifyRunning to (exists (application processes whose name is "Spotify"))
    end tell
    if spotifyRunning then
        tell application "Spotify"
            set playerStateText to (player state as text)
            if playerStateText is "playing" or playerStateText is "paused" then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to (duration of current track) as text
                set trackPosition to (player position) as text
                set artworkAddress to ""
                try
                    set artworkAddress to (artwork url of current track)
                end try
                set output to trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & trackDuration & linefeed & artworkAddress & linefeed & trackPosition & linefeed & playerStateText
            end if
        end tell
    end if
    return output
    """
}
