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

    var isHovering = false {
        didSet {
            guard isHovering != oldValue else { return }
            // Every time the island opens it starts fresh: Home (now playing)
            // tab and today's date — never left on Bluetooth/Shelf/another day.
            if isHovering {
                tab = .home
                calendar.focusToday()
            }
        }
    }

    /// True while a file drag is hovering the island (shows the drop zone).
    var isDropTargeting = false

    /// Keeps the island expanded briefly after a drop so the file is visible.
    var justDropped = false

    /// True briefly after the Mac unlocks (drives the padlock-open flash).
    var justUnlocked = false

    /// Distance from the very top of the screen down to the island's top edge
    /// (below the notch on notched Macs). Set by the window manager.
    var topInset: CGFloat = 32

    /// Physical notch size of the active display (`.zero` on notchless Macs).
    /// Used by the "part of the notch" style so the island fuses with the notch.
    var notchSize: CGSize = .zero

    var isNotchStyle: Bool { settings.islandStyle == .notch }

    /// Height taken up by the notch, so notch-style content clears it.
    var notchClearance: CGFloat {
        guard isNotchStyle else { return 0 }
        return notchSize.height > 0 ? notchSize.height : 34
    }

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

    /// Today's calendar events shown in the expanded card.
    @ObservationIgnored let calendar = CalendarService()

    /// Paired Bluetooth devices for the Bluetooth tab.
    @ObservationIgnored let bluetooth = BluetoothService()

    /// Which tab the expanded card is showing.
    enum Tab { case home, shelf, bluetooth }
    var tab: Tab = .home

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

    /// The UNSCALED content size of a presentation. The view lays content out at
    /// this size and scales the whole thing, so nothing ever clips.
    func baseSize(for presentation: Presentation) -> CGSize {
        if isNotchStyle {
            let nW = notchSize.width > 0 ? notchSize.width : 200
            let nH = notchSize.height > 0 ? notchSize.height : 34
            switch presentation {
            case .peek:
                // Flank the notch with art + visualizer while playing; else match it.
                return player.track != nil ? CGSize(width: nW + 116, height: max(nH, 34)) : CGSize(width: nW, height: nH)
            case .hud:
                return CGSize(width: max(nW + 150, 300), height: nH + 26)
            case .expanded:
                let e = expandedContentSize()
                return CGSize(width: max(nW + 200, e.width), height: nH + e.height)
            }
        }
        switch presentation {
        case .peek: return CGSize(width: 108, height: 32)
        case .hud: return CGSize(width: 240, height: 46)
        case .expanded: return expandedContentSize()
        }
    }

    func baseCornerRadius(for presentation: Presentation) -> CGFloat {
        if isNotchStyle {
            switch presentation {
            case .peek: return player.track != nil ? 12 : 8
            case .hud: return 20
            case .expanded: return 24
            }
        }
        switch presentation {
        case .peek: return baseSize(for: .peek).height / 2   // capsule
        case .hud: return baseSize(for: .hud).height / 2
        case .expanded: return 30
        }
    }

    /// Scale applied to a presentation. Expanded is driven ONLY by its own
    /// slider (independent of pod size); the resting pod uses the pod slider;
    /// the notch peek is never scaled so it matches the hardware notch exactly.
    func contentScale(for presentation: Presentation) -> CGFloat {
        if isNotchStyle && presentation == .peek { return 1 }
        return presentation == .expanded
            ? CGFloat(settings.islandExpandedScale)
            : CGFloat(settings.islandScale)
    }

    func layout(for presentation: Presentation) -> IslandLayout {
        let s = contentScale(for: presentation)
        let base = baseSize(for: presentation)
        return IslandLayout(width: base.width * s, height: base.height * s, cornerRadius: baseCornerRadius(for: presentation) * s)
    }

    /// The content size of the expanded card, before scale/notch clearance,
    /// driven by the current tab and whether the calendar column is shown.
    private func expandedContentSize() -> CGSize {
        if tab == .shelf {
            return CGSize(width: 460, height: 176)
        }
        if settings.islandShowCalendar {
            return CGSize(width: 600, height: 168)
        }
        // Media-only: still tall enough for the full media card (62pt artwork).
        return CGSize(width: 400, height: 152)
    }

    var currentLayout: IslandLayout { layout(for: presentation) }
}
