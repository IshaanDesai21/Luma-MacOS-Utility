import Foundation

/// A snapshot of what is currently playing in Spotify.
struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var duration: TimeInterval
    var position: TimeInterval
    var isPlaying: Bool

    /// Playback progress in the range `0...1`.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
