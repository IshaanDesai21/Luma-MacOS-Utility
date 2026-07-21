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

    private let gridColumns = [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 0) {
                appGrid
                Divider()
                selectionColumn
            }

            Divider()
            footer
        }
        .frame(width: 780, height: 600)
        .task { await catalog.loadIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(symbols, id: \.self) { option in
                    Button {
                        symbol = option
                    } label: {
                        Label(option, systemImage: option)
                    }
                }
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose a symbol")

            TextField("Workspace name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
        }
        .padding(16)
    }

    // MARK: - App grid (left)

    private var appGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(12)

            Divider()

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(filteredApps) { app in
                        appTile(app)
                    }
                }
                .padding(12)
            }
            .overlay {
                if catalog.isLoading {
                    ProgressView()
                } else if filteredApps.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .frame(width: 430)
    }

    private func appTile(_ app: InstalledApp) -> some View {
        let isOn = isSelected(app)
        return Button {
            toggle(app)
        } label: {
            VStack(spacing: 6) {
                Image(nsImage: catalog.icon(for: app.dockApp))
                    .resizable()
                    .frame(width: 40, height: 40)
                Text(app.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .tint)
                        .padding(5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isOn ? "Remove \(app.name)" : "Add \(app.name)")
    }

    // MARK: - Selection (right)

    private var selectionColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dock Preview")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            DockPreviewView(apps: selected, iconSize: 36)
                .padding(.horizontal, 16)

            if selected.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3.topleft.filled")
                        .font(.system(size: 26))
                        .foregroundStyle(.quaternary)
                    Text("Click apps on the left\nto build your Dock.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack {
                    Text("In this workspace")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("drag to reorder")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)

                List {
                    ForEach(selected) { app in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Image(nsImage: catalog.icon(for: app))
                                .resizable().frame(width: 22, height: 22)
                            Text(app.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                remove(app)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                        .padding(.vertical, 2)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { indices, destination in
                        selected.move(fromOffsets: indices, toOffset: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

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

    private func toggle(_ app: InstalledApp) {
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
