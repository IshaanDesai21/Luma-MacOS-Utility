import Foundation

/// The subset of `com.apple.dock` settings Luma can toggle.
struct DockPreferences: Equatable {
    enum Orientation: String, CaseIterable, Identifiable {
        case left, bottom, right
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum MinimizeEffect: String, CaseIterable, Identifiable {
        case genie, scale, suck
        var id: String { rawValue }
        var title: String {
            switch self {
            case .genie: return "Genie"
            case .scale: return "Scale"
            case .suck: return "Suck"
            }
        }
    }

    var autohide: Bool = false
    var magnification: Bool = false
    var tileSize: Double = 48
    var magnifiedSize: Double = 80
    var orientation: Orientation = .bottom
    var minimizeEffect: MinimizeEffect = .genie
    var minimizeToApplication: Bool = false
    var showRecents: Bool = true
    var animateOpening: Bool = true
    var showIndicators: Bool = true
    var showActiveOnly: Bool = false
}
