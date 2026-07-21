import Foundation

/// A named Dock layout the user can switch to.
///
/// A workspace is defined either by a *snapshot* of the live Dock (stored as a
/// `.plist` alongside it) or by a *manual* list of apps that Luma composes into
/// a Dock layout on demand.
struct Workspace: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case snapshot
        case manual
    }

    var id: UUID
    var name: String
    var symbol: String
    var kind: Kind
    var apps: [DockApp]

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "square.stack.3d.up",
        kind: Kind,
        apps: [DockApp] = []
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.kind = kind
        self.apps = apps
    }

    /// Filename for a snapshot workspace's stored Dock preferences.
    var snapshotFileName: String {
        "dock-\(id.uuidString).plist"
    }

    /// Default set shipped on first launch.
    static var defaults: [Workspace] {
        [
            Workspace(name: "Coding", symbol: "chevron.left.forwardslash.chevron.right", kind: .snapshot),
            Workspace(name: "Personal", symbol: "person.crop.circle", kind: .snapshot)
        ]
    }
}
