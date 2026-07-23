import Foundation

/// Best-effort bridge to the system-wide "Now Playing" info via the private
/// MediaRemote framework, loaded at runtime with `dlopen` so the app links
/// cleanly and degrades to nothing when the symbols aren't callable.
///
/// IMPORTANT: Apple gated `MRMediaRemoteGetNowPlayingInfo` behind a private
/// entitlement on macOS 15.4+, so third-party apps get empty results there.
/// This layer therefore only surfaces sources like browser video (YouTube) on
/// macOS 14.0-15.3; Spotify and Apple Music are handled by the reliable
/// AppleScript path regardless. Everything here fails soft.
final class MediaRemoteBridge: @unchecked Sendable {
    /// A cross-source now-playing snapshot plus the owning app's bundle id.
    struct Info {
        var title: String
        var artist: String
        var album: String
        var artworkData: Data?
        var duration: TimeInterval
        var elapsed: TimeInterval
        var isPlaying: Bool
        var bundleIdentifier: String?
    }

    /// True only if the framework loaded and the entry points resolved.
    let isAvailable: Bool

    // MediaRemote invokes these callbacks ASYNCHRONOUSLY (after the call
    // returns), so they must be `@escaping`. Swift auto-bridges the captured
    // Swift closure to an Objective-C block for the C function pointer; adding
    // an explicit `@convention(block)` here makes it non-escaping and traps.
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int, CFDictionary?) -> Bool

    private let getInfo: GetInfoFn?
    private let getIsPlaying: GetIsPlayingFn?
    private let sendCommand: SendCommandFn?
    private let callbackQueue = DispatchQueue(label: "com.luma.mediaremote", qos: .userInitiated)

    // MediaRemote command codes.
    private enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5
    }

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            isAvailable = false
            getInfo = nil; getIsPlaying = nil; sendCommand = nil
            return
        }
        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: type)
        }
        getInfo = sym("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self)
        getIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlayingFn.self)
        sendCommand = sym("MRMediaRemoteSendCommand", as: SendCommandFn.self)
        isAvailable = getInfo != nil
    }

    /// Guards a continuation so it resumes exactly once, whether by the
    /// MediaRemote callback or the safety timeout below — never both, never
    /// zero times (which would hang the caller forever).
    private final class OneShot<T>: @unchecked Sendable {
        private var continuation: CheckedContinuation<T, Never>?
        private let lock = NSLock()
        init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
        func resume(_ value: T) {
            lock.lock(); defer { lock.unlock() }
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    // MARK: - Reading

    /// Fetches the current system now-playing info, or nil if nothing / blocked.
    func fetch() async -> Info? {
        guard isAvailable, let getInfo else { return nil }
        let info: [AnyHashable: Any]? = await withCheckedContinuation { continuation in
            let shot = OneShot(continuation)
            getInfo(callbackQueue) { dict in shot.resume(dict as? [AnyHashable: Any]) }
            // If MediaRemote never calls back (blocked), don't hang the poll loop.
            callbackQueue.asyncAfter(deadline: .now() + 0.6) { shot.resume(nil) }
        }
        guard let info, !info.isEmpty else { return nil }

        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        let duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
        let elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0

        let isPlaying = await fetchIsPlaying(fallback: rate > 0)

        return Info(
            title: title,
            artist: artist,
            album: album,
            artworkData: artwork,
            duration: duration,
            elapsed: elapsed,
            isPlaying: isPlaying,
            bundleIdentifier: nil
        )
    }

    private func fetchIsPlaying(fallback: Bool) async -> Bool {
        guard let getIsPlaying else { return fallback }
        return await withCheckedContinuation { continuation in
            let shot = OneShot(continuation)
            getIsPlaying(callbackQueue) { playing in shot.resume(playing) }
            callbackQueue.asyncAfter(deadline: .now() + 0.6) { shot.resume(fallback) }
        }
    }

    // MARK: - Controls

    func togglePlayPause() { _ = sendCommand?(Command.togglePlayPause.rawValue, nil) }
    func next() { _ = sendCommand?(Command.next.rawValue, nil) }
    func previous() { _ = sendCommand?(Command.previous.rawValue, nil) }
}
