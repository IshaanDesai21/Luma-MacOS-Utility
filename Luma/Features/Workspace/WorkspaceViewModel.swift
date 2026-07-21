import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceViewModel {
    var selectionID: UUID?
    var isSwitching = false
    var succeededID: UUID?
    var errorMessage: String?
    var showError = false

    // Sheets / prompts
    var builderWorkspace: Workspace?
    var showBuilder = false
    var renameTarget: Workspace?
    var renameText = ""

    func selectFirstIfNeeded(_ store: WorkspaceStore) {
        if selectionID == nil { selectionID = store.workspaces.first?.id }
    }

    func selectedWorkspace(_ store: WorkspaceStore) -> Workspace? {
        store.workspaces.first { $0.id == selectionID }
    }

    // MARK: - Actions

    func apply(_ workspace: Workspace, using store: WorkspaceStore) async {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        do {
            try await store.apply(workspace)
            succeededID = workspace.id
            try? await Task.sleep(for: .milliseconds(1500))
            if succeededID == workspace.id { succeededID = nil }
        } catch {
            present(error)
        }
    }

    func updateSnapshot(_ workspace: Workspace, using store: WorkspaceStore) async {
        do {
            try await store.saveSnapshot(for: workspace)
            succeededID = workspace.id
        } catch {
            present(error)
        }
    }

    func addSnapshotWorkspace(using store: WorkspaceStore) async {
        let workspace = Workspace(name: "New Workspace", symbol: "square.stack.3d.up", kind: .snapshot)
        store.add(workspace)
        selectionID = workspace.id
        do {
            try await store.saveSnapshot(for: workspace)
        } catch {
            present(error)
        }
    }

    func beginBuild(_ workspace: Workspace? = nil) {
        builderWorkspace = workspace
        showBuilder = true
    }

    func commitBuild(_ workspace: Workspace, using store: WorkspaceStore) {
        if store.workspaces.contains(where: { $0.id == workspace.id }) {
            store.update(workspace)
        } else {
            store.add(workspace)
        }
        selectionID = workspace.id
    }

    func beginRename(_ workspace: Workspace) {
        renameTarget = workspace
        renameText = workspace.name
    }

    func commitRename(using store: WorkspaceStore) {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { store.rename(target, to: trimmed) }
        renameTarget = nil
    }

    func delete(_ workspace: Workspace, using store: WorkspaceStore) {
        store.delete(workspace)
        if selectionID == workspace.id {
            selectionID = store.workspaces.first?.id
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
