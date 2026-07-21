import Foundation

/// Reads and writes the live `com.apple.dock` feature settings, then restarts
/// the Dock so changes take effect.
struct DockPreferencesService {
    private let defaults = UserDefaults(suiteName: "com.apple.dock")

    // MARK: - Read

    func load() -> DockPreferences {
        var prefs = DockPreferences()
        guard let defaults else { return prefs }

        prefs.autohide = defaults.bool(forKey: Keys.autohide)
        prefs.magnification = defaults.bool(forKey: Keys.magnification)
        prefs.tileSize = number(defaults, Keys.tileSize, default: 48)
        prefs.magnifiedSize = number(defaults, Keys.largeSize, default: 80)
        prefs.orientation = DockPreferences.Orientation(rawValue: defaults.string(forKey: Keys.orientation) ?? "") ?? .bottom
        prefs.minimizeEffect = DockPreferences.MinimizeEffect(rawValue: defaults.string(forKey: Keys.minEffect) ?? "") ?? .genie
        prefs.minimizeToApplication = defaults.bool(forKey: Keys.minimizeToApp)
        prefs.showRecents = defaults.object(forKey: Keys.showRecents) as? Bool ?? true
        prefs.animateOpening = defaults.object(forKey: Keys.launchAnim) as? Bool ?? true
        prefs.showIndicators = defaults.object(forKey: Keys.showIndicators) as? Bool ?? true
        prefs.showActiveOnly = defaults.bool(forKey: Keys.staticOnly)
        return prefs
    }

    // MARK: - Write

    func apply(_ prefs: DockPreferences) async throws {
        guard let defaults else { return }

        defaults.set(prefs.autohide, forKey: Keys.autohide)
        defaults.set(prefs.magnification, forKey: Keys.magnification)
        defaults.set(prefs.tileSize, forKey: Keys.tileSize)
        defaults.set(prefs.magnifiedSize, forKey: Keys.largeSize)
        defaults.set(prefs.orientation.rawValue, forKey: Keys.orientation)
        defaults.set(prefs.minimizeEffect.rawValue, forKey: Keys.minEffect)
        defaults.set(prefs.minimizeToApplication, forKey: Keys.minimizeToApp)
        defaults.set(prefs.showRecents, forKey: Keys.showRecents)
        defaults.set(prefs.animateOpening, forKey: Keys.launchAnim)
        defaults.set(prefs.showIndicators, forKey: Keys.showIndicators)
        defaults.set(prefs.showActiveOnly, forKey: Keys.staticOnly)
        defaults.synchronize()

        try await ProcessRunner.run("/usr/bin/killall", arguments: ["Dock"], allowFailure: true)
    }

    private func number(_ defaults: UserDefaults, _ key: String, default fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    private enum Keys {
        static let autohide = "autohide"
        static let magnification = "magnification"
        static let tileSize = "tilesize"
        static let largeSize = "largesize"
        static let orientation = "orientation"
        static let minEffect = "mineffect"
        static let minimizeToApp = "minimize-to-application"
        static let showRecents = "show-recents"
        static let launchAnim = "launchanim"
        static let showIndicators = "show-process-indicators"
        static let staticOnly = "static-only"
    }
}
