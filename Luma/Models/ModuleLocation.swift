import Foundation

/// A surface where a module can appear.
enum ModuleLocation: String, CaseIterable, Identifiable, Codable {
    case sidebar
    case menuBar
    case dynamicIsland
    case notifications
    case keyboardShortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sidebar: return "Sidebar"
        case .menuBar: return "Menu Bar"
        case .dynamicIsland: return "Dynamic Island"
        case .notifications: return "Notifications"
        case .keyboardShortcut: return "Keyboard Shortcut"
        }
    }

    var symbol: String {
        switch self {
        case .sidebar: return "sidebar.left"
        case .menuBar: return "menubar.rectangle"
        case .dynamicIsland: return "waveform"
        case .notifications: return "bell"
        case .keyboardShortcut: return "command"
        }
    }
}
