import CoreGraphics
import Foundation
import Observation

/// State for the Dynamic Island overlay, derived from playback, hover, and file
/// drops. The single source of truth for the island's geometry: SwiftUI renders
/// exactly ``currentLayout`` and the window never resizes, so the two can't
/// disagree.
@MainActor
@Observable
final class DynamicIslandModel {
    enum Presentation: Equatable {
        case peek     // small resting glass pod
        case expanded // full media card dropped down
    }

    /// Geometry for one presentation, with the user's size setting baked in.
    struct IslandLayout: Equatable {
        var width: CGFloat
        var height: CGFloat
        var cornerRadius: CGFloat
    }

    var isHovering = false

    /// True while a file drag is hovering the island (shows the drop zone).
    var isDropTargeting = false

    /// Keeps the island expanded briefly after a drop so the file is visible.
    var justDropped = false

    /// True briefly after the Mac unlocks (drives the padlock-open flash).
    var justUnlocked = false

    /// Distance from the very top of the screen down to the island's top edge
    /// (below the notch on notched Macs). Set by the window manager.
    var topInset: CGFloat = 32

    @ObservationIgnored private var dropResetTask: Task<Void, Never>?
    @ObservationIgnored private var unlockResetTask: Task<Void, Never>?
    @ObservationIgnored private var unlockObserver: NSObjectProtocol?

    @ObservationIgnored let spotify: SpotifyService
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let shelf: FileShelf

    /// Camera/mic/charging state shown in the resting pod.
    @ObservationIgnored let sensors = SensorActivityService()

    init(spotify: SpotifyService, settings: AppSettings, shelf: FileShelf) {
        self.spotify = spotify
        self.settings = settings
        self.shelf = shelf
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteUnlock() }
        }
    }

    private func noteUnlock() {
        guard settings.islandUnlockGlow else { return }
        justUnlocked = true
        unlockResetTask?.cancel()
        unlockResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.justUnlocked = false
        }
    }

    func noteDrop() {
        justDropped = true
        dropResetTask?.cancel()
        dropResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.justDropped = false
        }
    }

    var presentation: Presentation {
        if isDropTargeting || justDropped { return .expanded }
        if settings.islandRevealOnHover, isHovering { return .expanded }
        return .peek
    }

    // MARK: - Geometry

    func layout(for presentation: Presentation) -> IslandLayout {
        let scale = CGFloat(settings.islandScale)
        switch presentation {
        case .peek:
            // A small pod: corner radius is exactly half the height, so the
            // shape is a true capsule at any scale.
            let height = 32 * scale
            return IslandLayout(width: 108 * scale, height: height, cornerRadius: height / 2)
        case .expanded:
            let tall = settings.islandFileShelf && (isDropTargeting || !shelf.items.isEmpty)
            return IslandLayout(width: 368 * scale, height: (tall ? 112 : 78) * scale, cornerRadius: 30 * scale)
        }
    }

    var currentLayout: IslandLayout { layout(for: presentation) }
}
