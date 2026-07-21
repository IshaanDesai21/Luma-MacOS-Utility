import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case dynamicIsland
    case menuBar
    case dock
    case workspace
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dynamicIsland: return "Dynamic Island"
        case .menuBar: return "Menu Bar"
        case .dock: return "Dock"
        case .workspace: return "Workspaces"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dynamicIsland: return "waveform"
        case .menuBar: return "menubar.rectangle"
        case .dock: return "dock.rectangle"
        case .workspace: return "macwindow"
        case .settings: return "gearshape"
        }
    }
}
