import SwiftUI

/// Sheet for composing a manual workspace: name it, pick a symbol, choose apps,
/// and see a live Dock preview.
struct WorkspaceBuilderView: View {
    @Environment(AppCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    let existing: Workspace?
    let onSave: (Workspace) -> Void

    @State private var name: String
    @State private var symbol: String
    @State private var selected: [DockApp]
    @State private var search = ""

    init(existing: Workspace? = nil, onSave: @escaping (Workspace) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _symbol = State(initialValue: existing?.symbol ?? "square.stack.3d.up")
        _selected = State(initialValue: existing?.apps ?? [])
    }

    private let symbols = [
        "square.stack.3d.up", "chevron.left.forwardslash.chevron.right",
        "person.crop.circle", "paintbrush.pointed", "gamecontroller",
        "briefcase", "music.note", "camera", "book"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 0) {
                availableList
                Divider()
                selectionColumn
            }
            .frame(minHeight: 360)

            Divider()
            footer
        }
        .frame(width: 720, height: 560)
        .task { await catalog.loadIfNeeded() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 34, height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            TextField("Workspace name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))

            Menu {
                ForEach(symbols, id: \.self) { option in
                    Button {
                        symbol = option
                    } label: {
                        Label(option, systemImage: option)
                    }
                }
            } label: {
                Label("Symbol", systemImage: "square.grid.2x2")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(16)
    }

    private var availableList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            Divider()

            List(filteredApps) { app in
                Button {
                    add(app)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: catalog.icon(for: app.dockApp))
                            .resizable().frame(width: 24, height: 24)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        if isSelected(app) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
            .overlay {
                if catalog.isLoading {
                    ProgressView()
                }
            }
        }
        .frame(width: 320)
    }

    private var selectionColumn: some View {
        VStack(spacing: 14) {
            Text("Dock Preview")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            DockPreviewView(apps: selected, iconSize: 40)
                .padding(.horizontal, 16)

            if selected.isEmpty {
                Spacer()
                Text("Select apps on the left to build your Dock.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            } else {
                List {
                    ForEach(selected) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: catalog.icon(for: app))
                                .resizable().frame(width: 22, height: 22)
                            Text(app.name).lineLimit(1)
                            Spacer()
                            Button {
                                remove(app)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { indices, destination in
                        selected.move(fromOffsets: indices, toOffset: destination)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("^[\(selected.count) app](inflect: true) selected")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(existing == nil ? "Create Workspace" : "Save Changes") {
                let workspace = Workspace(
                    id: existing?.id ?? UUID(),
                    name: name.isEmpty ? "New Workspace" : name,
                    symbol: symbol,
                    kind: .manual,
                    apps: selected
                )
                onSave(workspace)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return catalog.apps }
        return catalog.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func isSelected(_ app: InstalledApp) -> Bool {
        selected.contains { $0.path == app.path }
    }

    private func add(_ app: InstalledApp) {
        if isSelected(app) {
            remove(app.dockApp)
        } else {
            selected.append(app.dockApp)
        }
    }

    private func remove(_ app: DockApp) {
        selected.removeAll { $0.path == app.path }
    }
}
