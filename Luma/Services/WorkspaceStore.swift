import Foundation
import Observation

/// Owns the list of workspaces and persists their metadata to Application Support.
@MainActor
@Observable
final class WorkspaceStore {
    private(set) var workspaces: [Workspace]

    @ObservationIgnored private let dock: DockService
    @ObservationIgnored private let fileManager: FileManager

    private var indexURL: URL {
        dock.workspacesDirectory.appending(path: "workspaces.json")
    }

    init(dock: DockService = DockService(), fileManager: FileManager = .default) {
        self.dock = dock
        self.fileManager = fileManager
        self.workspaces = []
        self.workspaces = loadOrSeed()
    }

    // MARK: - Queries

    func hasSnapshot(_ workspace: Workspace) -> Bool {
        dock.hasSnapshot(for: workspace)
    }

    /// A workspace is ready to apply when it has a snapshot or at least one app.
    func canApply(_ workspace: Workspace) -> Bool {
        switch workspace.kind {
        case .snapshot: return dock.hasSnapshot(for: workspace)
        case .manual: return !workspace.apps.isEmpty
        }
    }

    // MARK: - Mutations

    func add(_ workspace: Workspace) {
        workspaces.append(workspace)
        persist()
    }

    func update(_ workspace: Workspace) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[index] = workspace
        persist()
    }

    func delete(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
        dock.deleteSnapshot(for: workspace)
        persist()
    }

    func rename(_ workspace: Workspace, to name: String) {
        guard var updated = workspaces.first(where: { $0.id == workspace.id }) else { return }
        updated.name = name
        update(updated)
    }

    // MARK: - Dock operations

    func saveSnapshot(for workspace: Workspace) async throws {
        try await dock.saveSnapshot(for: workspace)
    }

    func apply(_ workspace: Workspace) async throws {
        try await dock.apply(workspace)
    }

    // MARK: - Persistence

    private func loadOrSeed() -> [Workspace] {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Workspace].self, from: data),
              !decoded.isEmpty
        else {
            let seed = Workspace.defaults
            persist(seed)
            return seed
        }
        return decoded
    }

    private func persist() {
        persist(workspaces)
    }

    private func persist(_ workspaces: [Workspace]) {
        try? fileManager.createDirectory(at: dock.workspacesDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
