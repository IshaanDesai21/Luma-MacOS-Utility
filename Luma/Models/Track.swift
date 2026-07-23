import Foundation

/// A snapshot of what is currently playing, from any supported source.
struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    /// Remote artwork (Spotify). Prefer this when present.
    var artworkURL: URL?
    /// Inline artwork bytes (system now-playing / MediaRemote).
    var artworkData: Data?
    var duration: TimeInterval
    var position: TimeInterval
    var isPlaying: Bool

    init(
        title: String,
        artist: String,
        album: String,
        artworkURL: URL? = nil,
        artworkData: Data? = nil,
        duration: TimeInterval,
        position: TimeInterval,
        isPlaying: Bool
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.artworkData = artworkData
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
    }

    /// Playback progress in the range `0...1`.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
