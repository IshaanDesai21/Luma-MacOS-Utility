import Foundation
import Observation

/// Owns every module and its per-location configuration.
///
/// Registering a new module means adding one line to ``registerModules`` — all
/// surfacing is driven polymorphically through the ``Module`` protocol, so there
/// are no switch statements to update.
@MainActor
@Observable
final class ModuleManager {
    private(set) var modules: [Module]
    private(set) var configuration: ModuleConfiguration

    /// Bumped on any change so managers can observe and rebuild.
    private(set) var revision = 0

    @ObservationIgnored private let services: ModuleServices
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let storageKey = "modules.configuration"

    init(services: ModuleServices) {
        self.services = services
        self.modules = []
        self.configuration = .empty
        self.modules = Self.registerModules(services: services)
        self.configuration = loadConfiguration()
    }

    /// The single place a module is registered. Add your module here.
    private static func registerModules(services: ModuleServices) -> [Module] {
        [
            ClockModule(services: services),
            CalendarModule(services: services),
            TimerModule(services: services),
            SpotifyModule(services: services),
            MicrophoneModule(services: services),
            KeyboardModule(services: services),
            FileShelfModule(services: services),
            BatteryModule(services: services),
            CPUModule(services: services),
            MemoryModule(services: services),
            NetworkModule(services: services),
            DownloadsModule(services: services),
            ClipboardModule(services: services)
        ]
    }

    // MARK: - Queries

    func module(id: String) -> Module? {
        modules.first { $0.id == id }
    }

    func config(for module: Module) -> ModuleConfig {
        configuration.modules[module.id] ?? defaultConfig(for: module)
    }

    func isEnabled(_ module: Module) -> Bool {
        config(for: module).enabled
    }

    func isVisible(_ module: Module, in location: ModuleLocation) -> Bool {
        module.supportedLocations.contains(location)
            && isEnabled(module)
            && config(for: module).locations.contains(location)
    }

    func modules(for location: ModuleLocation) -> [Module] {
        let visible = modules.filter { isVisible($0, in: location) }
        guard location == .menuBar else { return visible }
        return ordered(visible)
    }

    /// Menu-bar modules in the user's chosen left-to-right order.
    func orderedMenuBarModules() -> [Module] {
        ordered(modules.filter { isVisible($0, in: .menuBar) })
    }

    /// Menu-bar modules that get their own status item.
    func individualMenuBarModules() -> [Module] {
        orderedMenuBarModules().filter { !isInMenuBarFolder($0) }
    }

    /// Menu-bar modules tucked behind the single "⋯" overflow button.
    func folderMenuBarModules() -> [Module] {
        orderedMenuBarModules().filter { isInMenuBarFolder($0) }
    }

    func isInMenuBarFolder(_ module: Module) -> Bool {
        configuration.menuBarFolder.contains(module.id)
    }

    func setInMenuBarFolder(_ inFolder: Bool, for module: Module) {
        if inFolder {
            configuration.menuBarFolder.insert(module.id)
        } else {
            configuration.menuBarFolder.remove(module.id)
        }
        bump()
    }

    private func ordered(_ list: [Module]) -> [Module] {
        let order = configuration.menuBarOrder
        return list.sorted { a, b in
            let ia = order.firstIndex(of: a.id) ?? Int.max
            let ib = order.firstIndex(of: b.id) ?? Int.max
            if ia != ib { return ia < ib }
            let ra = modules.firstIndex { $0.id == a.id } ?? 0
            let rb = modules.firstIndex { $0.id == b.id } ?? 0
            return ra < rb
        }
    }

    func isCompact(_ module: Module) -> Bool {
        config(for: module).compact
    }

    var collapseMenuBar: Bool { configuration.collapseMenuBar }

    // MARK: - Mutations

    func setEnabled(_ enabled: Bool, for module: Module) {
        var config = config(for: module)
        config.enabled = enabled
        apply(config, to: module)
    }

    func setLocation(_ location: ModuleLocation, enabled: Bool, for module: Module) {
        var config = config(for: module)
        if enabled {
            config.locations.insert(location)
        } else {
            config.locations.remove(location)
        }
        apply(config, to: module)
    }

    func setCollapseMenuBar(_ collapsed: Bool) {
        configuration.collapseMenuBar = collapsed
        bump()
    }

    func setCompact(_ compact: Bool, for module: Module) {
        var config = config(for: module)
        config.compact = compact
        apply(config, to: module)
    }

    /// Replace the full menu-bar order (used by drag-to-reorder in the preview).
    func setMenuBarOrder(_ ids: [String]) {
        configuration.menuBarOrder = ids
        bump()
    }

    /// Reorder for SwiftUI `List`'s `onMove`, operating on the ordered list.
    func moveMenuBarModules(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = orderedMenuBarModules().map(\.id)
        let moving = source.sorted().map { ids[$0] }
        for index in source.sorted(by: >) { ids.remove(at: index) }
        let removedBefore = source.filter { $0 < destination }.count
        let insertAt = min(max(destination - removedBefore, 0), ids.count)
        ids.insert(contentsOf: moving, at: insertAt)
        configuration.menuBarOrder = ids
        bump()
    }

    // MARK: - Helpers

    /// Modules that appear in the menu bar out of the box. Others are enabled but
    /// hidden from the menu bar by default so it doesn't get crowded (the user can
    /// switch them on per-module in the Modules page).
    private static let defaultMenuBar: Set<String> = ["clock", "battery", "cpu", "memory", "spotify", "microphone"]

    private func defaultConfig(for module: Module) -> ModuleConfig {
        var locations = module.supportedLocations
        if !Self.defaultMenuBar.contains(module.id) {
            locations.remove(.menuBar)
        }
        return ModuleConfig(enabled: true, locations: locations)
    }

    private func apply(_ config: ModuleConfig, to module: Module) {
        configuration.modules[module.id] = config
        bump()
    }

    private func bump() {
        revision += 1
        persist()
    }

    // MARK: - Persistence

    private func loadConfiguration() -> ModuleConfiguration {
        var loaded = ModuleConfiguration.empty
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ModuleConfiguration.self, from: data) {
            loaded = decoded
        }
        // Seed defaults for modules not yet present in storage.
        for module in modules where loaded.modules[module.id] == nil {
            loaded.modules[module.id] = defaultConfig(for: module)
        }
        return loaded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
