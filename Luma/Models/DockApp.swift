import Foundation

/// A single application reference used when manually composing a Dock layout.
struct DockApp: Codable, Identifiable, Hashable {
    var name: String
    var path: String
    var bundleID: String?

    var id: String { path }

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}
