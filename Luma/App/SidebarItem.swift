import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case workspace
    case dock
    case dynamicIsland
    case modules
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .dock: return "Dock"
        case .dynamicIsland: return "Dynamic Island"
        case .modules: return "Modules"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: return "macwindow"
        case .dock: return "dock.rectangle"
        case .dynamicIsland: return "waveform"
        case .modules: return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }
}
