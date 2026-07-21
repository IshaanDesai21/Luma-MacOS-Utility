import Foundation

enum DockServiceError: LocalizedError {
    case snapshotMissing
    case emptyAppList

    var errorDescription: String? {
        switch self {
        case .snapshotMissing:
            return "This workspace has no saved Dock yet. Use “Update Snapshot” first."
        case .emptyAppList:
            return "Add at least one app before applying this workspace."
        }
    }
}

/// Reads, composes, saves, and applies Dock layouts.
///
/// All reads/writes go through `defaults export`/`import` rather than touching
/// `com.apple.dock.plist` directly — `cfprefsd` caches that file, so direct
/// edits are unreliable (stale reads, ignored writes). `defaults` updates the
/// live preferences correctly, then `killall Dock` reloads them.
struct DockService {
    private let fileManager: FileManager
    private let defaultsTool = "/usr/bin/defaults"
    private let dockDomain = "com.apple.dock"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Locations

    var workspacesDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "Luma/Workspaces", directoryHint: .isDirectory)
    }

    func snapshotURL(for workspace: Workspace) -> URL {
        workspacesDirectory.appending(path: workspace.snapshotFileName)
    }

    func hasSnapshot(for workspace: Workspace) -> Bool {
        fileManager.fileExists(atPath: snapshotURL(for: workspace).path(percentEncoded: false))
    }

    // MARK: - Snapshot

    func saveSnapshot(for workspace: Workspace) async throws {
        try ensureWorkspacesDirectory()
        try await exportDomain(to: snapshotURL(for: workspace))
    }

    func deleteSnapshot(for workspace: Workspace) {
        try? fileManager.removeItem(at: snapshotURL(for: workspace))
    }

    // MARK: - Apply

    func apply(_ workspace: Workspace) async throws {
        switch workspace.kind {
        case .snapshot:
            guard hasSnapshot(for: workspace) else { throw DockServiceError.snapshotMissing }
            try await importDomain(from: snapshotURL(for: workspace))
        case .manual:
            guard !workspace.apps.isEmpty else { throw DockServiceError.emptyAppList }
            let composed = try await composeDockFile(with: workspace.apps)
            try await importDomain(from: composed)
            try? fileManager.removeItem(at: composed)
        }
        try await restartDock()
    }

    // MARK: - Composition

    /// Exports the current Dock, replaces `persistent-apps`, and writes a temp
    /// plist ready for `defaults import`.
    private func composeDockFile(with apps: [DockApp]) async throws -> URL {
        let base = temporaryPlistURL()
        try await exportDomain(to: base)

        var root = (try? readPlist(at: base)) ?? [:]
        root["persistent-apps"] = apps.map(makeTile)
        try? fileManager.removeItem(at: base)

        let output = temporaryPlistURL()
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        try data.write(to: output, options: .atomic)
        return output
    }

    private func makeTile(for app: DockApp) -> [String: Any] {
        [
            "tile-data": [
                "file-data": [
                    "_CFURLString": app.url.absoluteString,
                    "_CFURLStringType": 15
                ],
                "file-label": app.name,
                "file-type": 41
            ],
            "tile-type": "file-tile"
        ]
    }

    // MARK: - defaults / process helpers

    private func exportDomain(to url: URL) async throws {
        try await ProcessRunner.run(defaultsTool, arguments: ["export", dockDomain, url.path(percentEncoded: false)])
    }

    private func importDomain(from url: URL) async throws {
        try await ProcessRunner.run(defaultsTool, arguments: ["import", dockDomain, url.path(percentEncoded: false)])
    }

    private func restartDock() async throws {
        try await ProcessRunner.run("/usr/bin/killall", arguments: ["Dock"], allowFailure: true)
    }

    private func readPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return plist as? [String: Any] ?? [:]
    }

    private func temporaryPlistURL() -> URL {
        fileManager.temporaryDirectory.appending(path: "luma-dock-\(UUID().uuidString).plist")
    }

    private func ensureWorkspacesDirectory() throws {
        try fileManager.createDirectory(at: workspacesDirectory, withIntermediateDirectories: true)
    }
}
