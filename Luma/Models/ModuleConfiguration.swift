import Foundation

/// Per-module user state: whether it's enabled, which locations it appears in,
/// and whether it uses its compact (space-saving) menu-bar form.
struct ModuleConfig: Codable, Equatable {
    var enabled: Bool
    var locations: Set<ModuleLocation>
    var compact: Bool

    init(enabled: Bool, locations: Set<ModuleLocation>, compact: Bool = false) {
        self.enabled = enabled
        self.locations = locations
        self.compact = compact
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        // Tolerate location values that no longer exist (e.g. a removed surface).
        let raw = try c.decode([String].self, forKey: .locations)
        locations = Set(raw.compactMap(ModuleLocation.init(rawValue:)))
        compact = try c.decodeIfPresent(Bool.self, forKey: .compact) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(locations.map(\.rawValue), forKey: .locations)
        try c.encode(compact, forKey: .compact)
    }

    private enum CodingKeys: String, CodingKey { case enabled, locations, compact }
}

/// The full persisted configuration for all modules plus global options.
struct ModuleConfiguration: Codable, Equatable {
    var modules: [String: ModuleConfig]
    var collapseMenuBar: Bool
    /// User-chosen left-to-right order of menu-bar modules, by id. Ids absent
    /// here fall back to registration order, appended after the arranged ones.
    var menuBarOrder: [String]

    init(modules: [String: ModuleConfig], collapseMenuBar: Bool, menuBarOrder: [String] = []) {
        self.modules = modules
        self.collapseMenuBar = collapseMenuBar
        self.menuBarOrder = menuBarOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modules = try c.decode([String: ModuleConfig].self, forKey: .modules)
        collapseMenuBar = try c.decodeIfPresent(Bool.self, forKey: .collapseMenuBar) ?? false
        menuBarOrder = try c.decodeIfPresent([String].self, forKey: .menuBarOrder) ?? []
    }

    private enum CodingKeys: String, CodingKey { case modules, collapseMenuBar, menuBarOrder }

    static var empty: ModuleConfiguration {
        ModuleConfiguration(modules: [:], collapseMenuBar: false, menuBarOrder: [])
    }
}
