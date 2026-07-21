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
        case hud      // volume/brightness readout popped out of the notch
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

    @ObservationIgnored let player: NowPlayingService
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let shelf: FileShelf
    @ObservationIgnored let audio: AudioController
    @ObservationIgnored let brightness: BrightnessController
    @ObservationIgnored let monitor: SystemMonitor
    @ObservationIgnored let downloads: DownloadsService

    /// Camera/mic/charging state shown in the resting pod.
    @ObservationIgnored let sensors = SensorActivityService()

    init(
        player: NowPlayingService,
        settings: AppSettings,
        shelf: FileShelf,
        audio: AudioController,
        brightness: BrightnessController,
        monitor: SystemMonitor,
        downloads: DownloadsService
    ) {
        self.player = player
        self.settings = settings
        self.shelf = shelf
        self.audio = audio
        self.brightness = brightness
        self.monitor = monitor
        self.downloads = downloads
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

    // MARK: - Scroll-to-volume

    /// True briefly after a volume change so the pod can show the readout.
    var isVolumeFlashing = false

    /// True briefly after a brightness change (system HUD replacement).
    var isBrightnessFlashing = false

    @ObservationIgnored private var volumeFlashTask: Task<Void, Never>?
    @ObservationIgnored private var brightnessFlashTask: Task<Void, Never>?
    @ObservationIgnored private var scrollAccumulator: CGFloat = 0

    /// Scrolling over the pod nudges the system volume.
    func scrollVolume(by delta: CGFloat) {
        guard settings.islandScrollVolume else { return }
        // Accumulate small trackpad deltas into discrete volume steps.
        scrollAccumulator += delta
        let step: CGFloat = 6
        guard abs(scrollAccumulator) >= step else { return }
        let increments = Int(scrollAccumulator / step)
        scrollAccumulator -= CGFloat(increments) * step
        let newVolume = min(max(audio.volume + Float(increments) * 0.05, 0), 1)
        audio.setVolume(newVolume)
        flashVolume()
    }

    func flashVolume() {
        isVolumeFlashing = true
        isBrightnessFlashing = false
        volumeFlashTask?.cancel()
        volumeFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.isVolumeFlashing = false
        }
    }

    func flashBrightness() {
        isBrightnessFlashing = true
        isVolumeFlashing = false
        brightnessFlashTask?.cancel()
        brightnessFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.isBrightnessFlashing = false
        }
    }

    /// Battery is low and not on power — drives the red pod warning.
    var isLowBattery: Bool {
        settings.islandLowBatteryAlert
            && monitor.hasBattery
            && monitor.batteryLevel <= 0.15
            && !monitor.batteryCharging
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
        if settings.islandRevealOnHover || settings.islandHiddenUntilHover, isHovering { return .expanded }
        // Volume/brightness changes pop a readout out of the notch.
        if isVolumeFlashing || isBrightnessFlashing { return .hud }
        return .peek
    }

    /// True when the island should be invisible at rest (hidden-until-hover
    /// mode): the hover strip still works, everything else disappears.
    var isTuckedAway: Bool {
        settings.islandHiddenUntilHover && presentation == .peek
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
        case .hud:
            // The pop-out readout: a wider capsule that springs from the notch.
            let height = 46 * scale
            return IslandLayout(width: 240 * scale, height: height, cornerRadius: height / 2)
        case .expanded:
            let tall = settings.islandFileShelf && (isDropTargeting || !shelf.items.isEmpty)
            return IslandLayout(width: 368 * scale, height: (tall ? 112 : 78) * scale, cornerRadius: 30 * scale)
        }
    }

    var currentLayout: IslandLayout { layout(for: presentation) }
}
