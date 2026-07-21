import SwiftUI

struct RootView: View {
    @State private var selection: SidebarItem?

    init(initialItem: SidebarItem = .workspace) {
        _selection = State(initialValue: initialItem)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    row(.workspace)
                    row(.dock)
                    row(.dynamicIsland)
                }
                Section {
                    row(.modules)
                    row(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 260)
            .listStyle(.sidebar)
            .navigationTitle("Luma")
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol).tag(item)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .workspace {
        case .workspace: WorkspaceView()
        case .dock: DockSettingsView()
        case .dynamicIsland: DynamicIslandPageView()
        case .modules: ModulesView()
        case .settings: SettingsView()
        }
    }
}
