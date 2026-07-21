import CoreGraphics
import Observation

/// Presentation state for the Dynamic Island overlay, derived from playback and
/// hover. Shared between ``WindowManager`` (sizing) and the SwiftUI content.
@MainActor
@Observable
final class DynamicIslandModel {
    enum Presentation: Equatable {
        case hidden   // tucked into the notch
        case peek     // slim now-playing hint
        case expanded // full media card dropped down
    }

    var isHovering = false

    /// True while a file drag is hovering the island (shows the drop zone).
    var isDropTargeting = false

    /// Keeps the island expanded briefly after a drop so the file is visible.
    var justDropped = false

    @ObservationIgnored private var dropResetTask: Task<Void, Never>?

    func noteDrop() {
        justDropped = true
        dropResetTask?.cancel()
        dropResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.justDropped = false
        }
    }

    /// Vertical inset that keeps content clear of the notch / menu bar.
    var topInset: CGFloat = 32

    @ObservationIgnored let spotify: SpotifyService
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let shelf: FileShelf

    init(spotify: SpotifyService, settings: AppSettings, shelf: FileShelf) {
        self.spotify = spotify
        self.settings = settings
        self.shelf = shelf
    }

    var presentation: Presentation {
        if isDropTargeting || justDropped { return .expanded }
        if settings.islandRevealOnHover, isHovering {
            return .expanded
        }
        // Resting state is always the small glass preview so the island is
        // reliably visible; disable the island entirely to hide it.
        return .peek
    }

    // MARK: - Shape metrics (shared by the view and the window manager)

    struct Metrics: Equatable {
        var width: CGFloat
        var height: CGFloat
        var radius: CGFloat
        var shadow: CGFloat
        var shadowY: CGFloat
    }

    func metrics(for presentation: Presentation) -> Metrics {
        switch presentation {
        case .hidden:
            return Metrics(width: 110, height: 7, radius: 4, shadow: 0, shadowY: 0)
        case .peek:
            return Metrics(width: 104, height: 34, radius: 17, shadow: 9, shadowY: 3)
        case .expanded:
            return Metrics(width: 360, height: 76, radius: 26, shadow: 16, shadowY: 7)
        }
    }

    var currentMetrics: Metrics {
        var metrics = metrics(for: presentation)
        if presentation == .expanded, isDropTargeting || !shelf.items.isEmpty {
            metrics.height = 112
        }
        return metrics
    }
}
