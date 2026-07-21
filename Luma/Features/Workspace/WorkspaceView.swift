import SwiftUI

struct WorkspaceView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var viewModel = WorkspaceViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(spacing: 28) {
                PageHeader(
                    title: "Workspace",
                    subtitle: "Switch your Dock between saved layouts."
                )

                workspaceCard
                    .frame(maxWidth: 460)

                addButton

                if let workspace = viewModel.selectedWorkspace(store) {
                    detail(for: workspace)
                        .frame(maxWidth: 460)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Workspace")
        .onAppear { viewModel.selectFirstIfNeeded(store) }
        .sheet(isPresented: $viewModel.showBuilder) {
            WorkspaceBuilderView(existing: viewModel.builderWorkspace) { workspace in
                viewModel.commitBuild(workspace, using: store)
            }
        }
        .alert("Rename Workspace", isPresented: renameBinding) {
            TextField("Name", text: $viewModel.renameText)
            Button("Save") { viewModel.commitRename(using: store) }
            Button("Cancel", role: .cancel) { viewModel.renameTarget = nil }
        }
        .alert(
            "Something went wrong",
            isPresented: $viewModel.showError,
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    // MARK: - Workspace list

    private var workspaceCard: some View {
        VStack(spacing: 0) {
            ForEach(store.workspaces) { workspace in
                row(for: workspace)
                if workspace.id != store.workspaces.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(settings.glassMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var addButton: some View {
        Menu {
            Button {
                Task { await viewModel.addSnapshotWorkspace(using: store) }
            } label: {
                Label("New from Current Dock", systemImage: "square.and.arrow.down")
            }
            Button {
                viewModel.beginBuild(nil)
            } label: {
                Label("Build from Apps…", systemImage: "square.grid.2x2")
            }
        } label: {
            Label("Add Workspace", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fixedSize()
    }

    private func row(for workspace: Workspace) -> some View {
        Button {
            viewModel.selectionID = workspace.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: workspace.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.name)
                    Text(workspace.kind == .snapshot ? "Snapshot" : "^[\(workspace.apps.count) app](inflect: true)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.selectionID == workspace.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") { viewModel.beginRename(workspace) }
            if workspace.kind == .manual {
                Button("Edit Apps") { viewModel.beginBuild(workspace) }
            }
            Divider()
            Button("Delete", role: .destructive) { viewModel.delete(workspace, using: store) }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(for workspace: Workspace) -> some View {
        VStack(spacing: 16) {
            if workspace.kind == .manual {
                DockPreviewView(apps: workspace.apps)
            }

            Button {
                Task { await viewModel.apply(workspace, using: store) }
            } label: {
                Label(switchLabel(for: workspace), systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.canApply(workspace) || viewModel.isSwitching)

            secondaryButton(for: workspace)

            statusLine(for: workspace)
                .frame(height: 20)
        }
    }

    @ViewBuilder
    private func secondaryButton(for workspace: Workspace) -> some View {
        switch workspace.kind {
        case .snapshot:
            Button {
                Task { await viewModel.updateSnapshot(workspace, using: store) }
            } label: {
                Label("Update Snapshot", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .manual:
            Button {
                viewModel.beginBuild(workspace)
            } label: {
                Label("Edit Apps", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func statusLine(for workspace: Workspace) -> some View {
        if viewModel.isSwitching {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Switching…")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        } else if viewModel.succeededID == workspace.id {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .transition(.opacity)
        } else if !store.canApply(workspace) {
            Text(workspace.kind == .snapshot ? "No snapshot saved yet." : "Add at least one app.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func switchLabel(for workspace: Workspace) -> String {
        "Switch to \(workspace.name)"
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { viewModel.renameTarget != nil },
            set: { if !$0 { viewModel.renameTarget = nil } }
        )
    }
}
