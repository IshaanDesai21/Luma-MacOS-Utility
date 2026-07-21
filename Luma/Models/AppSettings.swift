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
    enum GlassIntensity: String, CaseIterable, Identifiable {
        case ultraThin, thin, regular, thick

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ultraThin: return "Clear"
            case .thin: return "Light"
            case .regular: return "Regular"
            case .thick: return "Frosted"
            }
        }

        var material: Material {
            switch self {
            case .ultraThin: return .ultraThinMaterial
            case .thin: return .thinMaterial
            case .regular: return .regularMaterial
            case .thick: return .thickMaterial
            }
        }

        /// A milky frost layer drawn over the glass; higher levels read as more
        /// opaque/frosted. Drives the visible difference between levels on the
        /// macOS 26 glass path (where `glassEffect` has only clear/regular).
        var frostScrim: Double {
            switch self {
            case .ultraThin: return 0.0
            case .thin: return 0.12
            case .regular: return 0.24
            case .thick: return 0.40
            }
        }

        /// Whether to use the barely-there `.clear` glass on macOS 26.
        var prefersClearGlass: Bool { self == .ultraThin }
    }

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

    var glassIntensity: GlassIntensity {
        didSet { defaults.set(glassIntensity.rawValue, forKey: Keys.glassIntensity) }
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

    /// Overall island size multiplier.
    var islandScale: Double {
        didSet { defaults.set(islandScale, forKey: Keys.islandScale) }
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

    var glassMaterial: Material { glassIntensity.material }

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
        static let glassIntensity = "settings.glassIntensity"
        static let islandEnabled = "island.enabled"
        static let islandRevealOnHover = "island.revealOnHover"
        static let islandShowWhilePlaying = "island.showWhilePlaying"
        static let islandVerticalOffset = "island.verticalOffset"
        static let islandHorizontalOffset = "island.horizontalOffset"
        static let islandScale = "island.scale"
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

        glassIntensity = GlassIntensity(rawValue: defaults.string(forKey: Keys.glassIntensity) ?? "") ?? .regular

        islandEnabled = defaults.object(forKey: Keys.islandEnabled) as? Bool ?? true
        islandRevealOnHover = defaults.object(forKey: Keys.islandRevealOnHover) as? Bool ?? true
        islandShowWhilePlaying = defaults.object(forKey: Keys.islandShowWhilePlaying) as? Bool ?? true
        islandVerticalOffset = defaults.double(forKey: Keys.islandVerticalOffset)
        islandHorizontalOffset = defaults.double(forKey: Keys.islandHorizontalOffset)
        let storedScale = defaults.double(forKey: Keys.islandScale)
        islandScale = storedScale == 0 ? 1.0 : storedScale
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
