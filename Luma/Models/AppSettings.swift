import SwiftUI
import Observation
import AppKit

/// User-facing preferences, persisted in `UserDefaults` and applied app-wide.
@MainActor
@Observable
final class AppSettings {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Controls how translucent the app's glass surfaces appear.
    /// Continuous Liquid Glass amount: 0 = water-clear "very liquid" glass,
    /// 1 = fully frosted. Everything glassy derives from this one number.
    /// Set via `glassLevel`.

    var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }

    /// Multiplier where `1.0` is the baseline. Higher is faster.
    var animationSpeed: Double {
        didSet { defaults.set(animationSpeed, forKey: Keys.animationSpeed) }
    }

    var glassLevel: Double {
        didSet { defaults.set(glassLevel, forKey: Keys.glassLevel) }
    }

    // Dynamic Island behaviour.
    var islandEnabled: Bool {
        didSet { defaults.set(islandEnabled, forKey: Keys.islandEnabled) }
    }

    var islandRevealOnHover: Bool {
        didSet { defaults.set(islandRevealOnHover, forKey: Keys.islandRevealOnHover) }
    }

    /// Points to raise (+) or lower (−) the island. Lower it to clear the menu bar.
    var islandVerticalOffset: Double {
        didSet { defaults.set(islandVerticalOffset, forKey: Keys.islandVerticalOffset) }
    }

    /// Points to shift the island left (−) or right (+) to dodge menu bar items.
    var islandHorizontalOffset: Double {
        didSet { defaults.set(islandHorizontalOffset, forKey: Keys.islandHorizontalOffset) }
    }

    /// Overall island size multiplier (the resting pod).
    var islandScale: Double {
        didSet { defaults.set(islandScale, forKey: Keys.islandScale) }
    }

    /// Extra multiplier applied only to the expanded card, so it can be smaller
    /// (or larger) than the pod's size.
    var islandExpandedScale: Double {
        didSet { defaults.set(islandExpandedScale, forKey: Keys.islandExpandedScale) }
    }

    /// Size multiplier for the hover strip that opens the island (1 = default).
    var islandActivationArea: Double {
        didSet { defaults.set(islandActivationArea, forKey: Keys.islandActivationArea) }
    }

    // MARK: Island feature toggles

    /// Green/orange dots in the pod while any app uses the camera/mic.
    var islandShowSensors: Bool {
        didSet { defaults.set(islandShowSensors, forKey: Keys.islandShowSensors) }
    }

    /// Green bolt in the pod while the Mac is charging.
    var islandChargingIndicator: Bool {
        didSet { defaults.set(islandChargingIndicator, forKey: Keys.islandChargingIndicator) }
    }

    /// Show the time in the pod when nothing is playing.
    var islandShowClockIdle: Bool {
        didSet { defaults.set(islandShowClockIdle, forKey: Keys.islandShowClockIdle) }
    }

    /// Seek bar inside the expanded media card.
    var islandShowSeekBar: Bool {
        didSet { defaults.set(islandShowSeekBar, forKey: Keys.islandShowSeekBar) }
    }

    /// Accept file drops and keep them on the island shelf.
    var islandFileShelf: Bool {
        didSet { defaults.set(islandFileShelf, forKey: Keys.islandFileShelf) }
    }

    /// Little bounce of the pod when the track changes.
    var islandTrackPulse: Bool {
        didSet { defaults.set(islandTrackPulse, forKey: Keys.islandTrackPulse) }
    }

    /// Padlock-open flash when the Mac unlocks.
    var islandUnlockGlow: Bool {
        didSet { defaults.set(islandUnlockGlow, forKey: Keys.islandUnlockGlow) }
    }

    /// Animated equalizer bars in the pod while music plays.
    var islandVisualizer: Bool {
        didSet { defaults.set(islandVisualizer, forKey: Keys.islandVisualizer) }
    }

    /// Scroll on the pod to change system volume.
    var islandScrollVolume: Bool {
        didSet { defaults.set(islandScrollVolume, forKey: Keys.islandScrollVolume) }
    }

    /// Click the pod to play/pause (when reveal-on-hover is off).
    var islandClickPlayPause: Bool {
        didSet { defaults.set(islandClickPlayPause, forKey: Keys.islandClickPlayPause) }
    }

    /// Red battery flash in the pod when low and not charging.
    var islandLowBatteryAlert: Bool {
        didSet { defaults.set(islandLowBatteryAlert, forKey: Keys.islandLowBatteryAlert) }
    }

    /// First-run setup assistant has been finished (or skipped).
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// How the island sits on screen.
    enum IslandStyle: String, CaseIterable, Identifiable {
        /// A floating glass pod below the notch.
        case floating
        /// Seamlessly attached to the physical notch, boringNotch style: solid
        /// black, flat top, notch width, so it reads as the notch itself.
        case notch

        var id: String { rawValue }
        var title: String {
            switch self {
            case .floating: return "Floating pod"
            case .notch: return "Part of the notch"
            }
        }
    }

    var islandStyle: IslandStyle {
        didSet { defaults.set(islandStyle.rawValue, forKey: Keys.islandStyle) }
    }

    /// Solid black island (classic iPhone look) instead of Liquid Glass.
    var islandSolidBlack: Bool {
        didSet { defaults.set(islandSolidBlack, forKey: Keys.islandSolidBlack) }
    }

    /// Replace the system volume/brightness bezel with the island's readout.
    var islandSystemHUD: Bool {
        didSet { defaults.set(islandSystemHUD, forKey: Keys.islandSystemHUD) }
    }

    /// Show an indicator in the pod while files are downloading.
    var islandDownloadProgress: Bool {
        didSet { defaults.set(islandDownloadProgress, forKey: Keys.islandDownloadProgress) }
    }

    /// Keep the island invisible until the cursor reaches the notch area.
    var islandHiddenUntilHover: Bool {
        didSet { defaults.set(islandHiddenUntilHover, forKey: Keys.islandHiddenUntilHover) }
    }

    /// Strength of the album-artwork glow around the island (0 = off).
    var islandGlowAmount: Double {
        didSet { defaults.set(islandGlowAmount, forKey: Keys.islandGlowAmount) }
    }

    /// Show today's calendar beside the media card in the expanded island.
    var islandShowCalendar: Bool {
        didSet { defaults.set(islandShowCalendar, forKey: Keys.islandShowCalendar) }
    }

    var islandShowWhilePlaying: Bool {
        didSet { defaults.set(islandShowWhilePlaying, forKey: Keys.islandShowWhilePlaying) }
    }

    /// When true, the window always opens to the Settings page.
    var launchOnSettings: Bool {
        didSet { defaults.set(launchOnSettings, forKey: Keys.launchOnSettings) }
    }

    /// Click the active app's Dock icon to minimize it (needs Accessibility).
    var dockClickToHide: Bool {
        didSet { defaults.set(dockClickToHide, forKey: Keys.dockClickToHide) }
    }

    var islandHideShortcut: GlobalShortcut? {
        didSet { persist(islandHideShortcut, forKey: Keys.islandHideShortcut) }
    }

    var micMuteShortcut: GlobalShortcut? {
        didSet { persist(micMuteShortcut, forKey: Keys.micMuteShortcut) }
    }

    private(set) var launchAtLogin: Bool

    // MARK: - Derived

    /// Material for glass card backgrounds, bucketed from the continuous level.
    var glassMaterial: Material {
        switch glassLevel {
        case ..<0.25: return .ultraThinMaterial
        case ..<0.5: return .thinMaterial
        case ..<0.75: return .regularMaterial
        default: return .thickMaterial
        }
    }

    var springAnimation: Animation {
        let response = 0.42 / max(animationSpeed, 0.1)
        return .spring(response: response, dampingFraction: 0.82)
    }

    /// Duration used for the island's size change; matched to the window's frame
    /// animation so the two never fight.
    var islandAnimationDuration: Double { 0.34 / max(animationSpeed, 0.1) }

    var islandAnimation: Animation { .easeInOut(duration: islandAnimationDuration) }

    private let defaults: UserDefaults

    private enum Keys {
        static let appearance = "settings.appearance"
        static let animationSpeed = "settings.animationSpeed"
        static let glassIntensity = "settings.glassIntensity"   // legacy 4-level value, migrated
        static let glassLevel = "settings.glassLevel"
        static let islandEnabled = "island.enabled"
        static let islandRevealOnHover = "island.revealOnHover"
        static let islandShowWhilePlaying = "island.showWhilePlaying"
        static let islandVerticalOffset = "island.verticalOffset"
        static let islandHorizontalOffset = "island.horizontalOffset"
        static let islandScale = "island.scale"
        static let islandExpandedScale = "island.expandedScale"
        static let islandActivationArea = "island.activationArea"
        static let islandShowSensors = "island.showSensors"
        static let islandChargingIndicator = "island.chargingIndicator"
        static let islandShowClockIdle = "island.showClockIdle"
        static let islandShowSeekBar = "island.showSeekBar"
        static let islandFileShelf = "island.fileShelf"
        static let islandTrackPulse = "island.trackPulse"
        static let islandUnlockGlow = "island.unlockGlow"
        static let islandVisualizer = "island.visualizer"
        static let islandScrollVolume = "island.scrollVolume"
        static let islandClickPlayPause = "island.clickPlayPause"
        static let islandLowBatteryAlert = "island.lowBatteryAlert"
        static let hasCompletedOnboarding = "app.hasCompletedOnboarding"
        static let islandSolidBlack = "island.solidBlack"
        static let islandStyle = "island.style"
        static let islandSystemHUD = "island.systemHUD"
        static let islandDownloadProgress = "island.downloadProgress"
        static let islandHiddenUntilHover = "island.hiddenUntilHover"
        static let islandGlowAmount = "island.glowAmount"
        static let islandShowCalendar = "island.showCalendar"
        static let launchOnSettings = "app.launchOnSettings"
        static let dockClickToHide = "dock.clickToHide"
        static let islandHideShortcut = "shortcut.islandHide"
        static let micMuteShortcut = "shortcut.micMute"
    }

    private func persist(_ shortcut: GlobalShortcut?, forKey key: String) {
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func loadShortcut(_ defaults: UserDefaults, _ key: String) -> GlobalShortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GlobalShortcut.self, from: data)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system

        let storedSpeed = defaults.double(forKey: Keys.animationSpeed)
        animationSpeed = storedSpeed == 0 ? 1.0 : storedSpeed

        if defaults.object(forKey: Keys.glassLevel) != nil {
            glassLevel = defaults.double(forKey: Keys.glassLevel)
        } else {
            // Migrate the old 4-level picker value onto the continuous slider.
            switch defaults.string(forKey: Keys.glassIntensity) {
            case "ultraThin": glassLevel = 0.05
            case "thin": glassLevel = 0.35
            case "thick": glassLevel = 0.9
            default: glassLevel = 0.55
            }
        }

        islandEnabled = defaults.object(forKey: Keys.islandEnabled) as? Bool ?? true
        islandRevealOnHover = defaults.object(forKey: Keys.islandRevealOnHover) as? Bool ?? true
        islandShowWhilePlaying = defaults.object(forKey: Keys.islandShowWhilePlaying) as? Bool ?? true
        islandVerticalOffset = defaults.double(forKey: Keys.islandVerticalOffset)
        islandHorizontalOffset = defaults.double(forKey: Keys.islandHorizontalOffset)
        let storedScale = defaults.double(forKey: Keys.islandScale)
        islandScale = storedScale == 0 ? 1.0 : storedScale
        let storedExpanded = defaults.double(forKey: Keys.islandExpandedScale)
        islandExpandedScale = storedExpanded == 0 ? 1.0 : storedExpanded
        let storedActivation = defaults.double(forKey: Keys.islandActivationArea)
        islandActivationArea = storedActivation == 0 ? 1.0 : storedActivation
        // Feature toggles default to on (except the idle clock).
        func flag(_ key: String, default def: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? def : defaults.bool(forKey: key)
        }
        islandShowSensors = flag(Keys.islandShowSensors, default: true)
        islandChargingIndicator = flag(Keys.islandChargingIndicator, default: true)
        islandShowClockIdle = flag(Keys.islandShowClockIdle, default: false)
        islandShowSeekBar = flag(Keys.islandShowSeekBar, default: true)
        islandFileShelf = flag(Keys.islandFileShelf, default: true)
        islandTrackPulse = flag(Keys.islandTrackPulse, default: true)
        islandUnlockGlow = flag(Keys.islandUnlockGlow, default: true)
        islandVisualizer = flag(Keys.islandVisualizer, default: true)
        islandScrollVolume = flag(Keys.islandScrollVolume, default: true)
        islandClickPlayPause = flag(Keys.islandClickPlayPause, default: true)
        islandLowBatteryAlert = flag(Keys.islandLowBatteryAlert, default: true)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        islandSolidBlack = flag(Keys.islandSolidBlack, default: false)
        islandStyle = IslandStyle(rawValue: defaults.string(forKey: Keys.islandStyle) ?? "") ?? .floating
        islandSystemHUD = flag(Keys.islandSystemHUD, default: true)
        islandDownloadProgress = flag(Keys.islandDownloadProgress, default: true)
        islandHiddenUntilHover = flag(Keys.islandHiddenUntilHover, default: false)
        let storedGlow = defaults.object(forKey: Keys.islandGlowAmount) as? Double
        islandGlowAmount = storedGlow ?? 0.35
        islandShowCalendar = flag(Keys.islandShowCalendar, default: true)
        launchOnSettings = defaults.bool(forKey: Keys.launchOnSettings)
        dockClickToHide = defaults.bool(forKey: Keys.dockClickToHide)
        islandHideShortcut = Self.loadShortcut(defaults, Keys.islandHideShortcut)
        micMuteShortcut = Self.loadShortcut(defaults, Keys.micMuteShortcut)

        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLogin = enabled
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
