import SwiftUI
import AppKit

final class SpotifyModule: ModuleObject, Module {
    let id = "spotify"
    let name = "Spotify"
    let icon = "music.note"
    let supportedLocations: Set<ModuleLocation> = [.menuBar, .dynamicIsland]

    func menuBarView() -> AnyView? {
        AnyView(Chip(services.spotify))
    }

    func menuBarPopover() -> AnyView? {
        AnyView(NowPlaying(spotify: services.spotify))
    }

    func dynamicIslandView() -> AnyView? {
        AnyView(NowPlaying(spotify: services.spotify))
    }

    private struct Chip: View {
        let spotify: SpotifyService
        init(_ spotify: SpotifyService) { self.spotify = spotify }
        var body: some View {
            if let track = spotify.track {
                MenuBarChip(systemImage: "music.note", text: track.title)
            } else {
                MenuBarChip(systemImage: "music.note", text: "")
            }
        }
    }

    private struct NowPlaying: View {
        let spotify: SpotifyService
        var body: some View {
            if let track = spotify.track {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    control("backward.fill") { spotify.previousTrack() }
                    control(track.isPlaying ? "pause.fill" : "play.fill") { spotify.playPause() }
                    control("forward.fill") { spotify.nextTrack() }
                }
                .frame(minWidth: 220)
            } else {
                Text("Nothing playing").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }

        private func control(_ symbol: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
    }
}
