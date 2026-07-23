import AppKit
import Foundation
import Observation

/// System-wide "Now Playing" via the `ungive/mediaremote-adapter` helper, which
/// keeps working on macOS 15.4+ where Apple gated the raw MediaRemote calls.
///
/// It spawns the bundled Perl helper in `stream` mode and parses its JSON lines
/// (title/artist/album/artwork/elapsed/playing/bundle id) for ANY player,
/// including browser video. Playback commands are sent via the helper's `send`.
///
/// SETUP (one-time, from https://github.com/ungive/mediaremote-adapter):
/// add `mediaremote-adapter.pl` and `MediaRemoteAdapter.framework` to the Xcode
/// project's **Copy Bundle Resources** phase. When they're absent this service
/// simply reports `isAvailable == false` and Luma falls back to AppleScript.
@MainActor
@Observable
final class MediaRemoteAdapterService {
    struct NowPlaying: Equatable {
        var title: String
        var artist: String
        var album: String
        var artworkData: Data?
        var duration: TimeInterval
        var elapsed: TimeInterval
        var isPlaying: Bool
        var bundleIdentifier: String?
    }

    private(set) var current: NowPlaying?

    @ObservationIgnored private var streamProcess: Process?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var onUpdate: ((NowPlaying?) -> Void)?

    /// Both helper files present in the bundle → the adapter can run.
    var isAvailable: Bool { scriptURL != nil && frameworkURL != nil }

    private var scriptURL: URL? {
        Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
    }

    private var frameworkURL: URL? {
        Bundle.main.url(forResource: "MediaRemoteAdapter", withExtension: "framework")
            ?? Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework")
    }

    // MARK: - Lifecycle

    func start(onUpdate: @escaping (NowPlaying?) -> Void) {
        guard isAvailable, streamProcess == nil,
              let scriptURL, let frameworkURL else { return }
        self.onUpdate = onUpdate

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkURL.path, "stream"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.consume(chunk) }
        }

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamProcess = nil }
        }

        do {
            try process.run()
            streamProcess = process
        } catch {
            streamProcess = nil
        }
    }

    func stop() {
        streamProcess?.terminate()
        streamProcess = nil
        buffer.removeAll()
        current = nil
    }

    // MARK: - Commands (route to the active player)

    func play() { send("play") }
    func pause() { send("pause") }
    func togglePlayPause() { send("togglePlayPause") }
    func next() { send("nextTrack") }
    func previous() { send("previousTrack") }
    func seek(to seconds: TimeInterval) { send("setElapsedTime", argument: String(format: "%.2f", seconds)) }

    private func send(_ command: String, argument: String? = nil) {
        guard isAvailable, let scriptURL, let frameworkURL else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        var args = [scriptURL.path, frameworkURL.path, "send", command]
        if let argument { args.append(argument) }
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - Stream parsing

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        // The helper emits one JSON object per line.
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !lineData.isEmpty else { continue }
            if let np = Self.parse(lineData) {
                current = np
                onUpdate?(np)
            }
        }
    }

    /// Defensive parse: accepts the fields at the top level or inside a
    /// `payload`, and tolerates missing keys. An empty title means "nothing".
    private static func parse(_ data: Data) -> NowPlaying? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let payload = (object["payload"] as? [String: Any]) ?? object

        func string(_ keys: [String]) -> String? {
            for k in keys { if let v = payload[k] as? String, !v.isEmpty { return v } }
            return nil
        }
        func number(_ keys: [String]) -> Double? {
            for k in keys {
                if let v = payload[k] as? Double { return v }
                if let v = payload[k] as? Int { return Double(v) }
                if let v = payload[k] as? NSNumber { return v.doubleValue }
            }
            return nil
        }

        guard let title = string(["title", "name", "Title", "Name"]) else { return nil }

        let playing = (payload["playing"] as? Bool)
            ?? (payload["isPlaying"] as? Bool)
            ?? ((number(["playbackRate", "rate"]) ?? 0) > 0)

        var artwork: Data?
        if let b64 = string(["artworkData", "artwork", "ArtworkData"]) {
            artwork = Data(base64Encoded: b64)
        }

        return NowPlaying(
            title: title,
            artist: string(["artist", "Artist"]) ?? "",
            album: string(["album", "Album"]) ?? "",
            artworkData: artwork,
            duration: number(["duration", "Duration", "totalTime"]) ?? 0,
            elapsed: number(["elapsedTime", "elapsed", "position"]) ?? 0,
            isPlaying: playing,
            bundleIdentifier: string(["bundleIdentifier", "bundleID"])
        )
    }
}
