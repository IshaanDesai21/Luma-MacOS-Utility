import SwiftUI

struct RootView: View {
    @State private var selection: SidebarItem?

    init(initialItem: SidebarItem = .dynamicIsland) {
        _selection = State(initialValue: initialItem)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Customize") {
                    row(.dynamicIsland)
                    row(.menuBar)
                    row(.dock)
                }
                Section("Workflows") {
                    row(.workspace)
                }
                Section("General") {
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
        switch selection ?? .dynamicIsland {
        case .dynamicIsland: DynamicIslandPageView()
        case .menuBar: ModulesView()
        case .dock: DockSettingsView()
        case .workspace: WorkspaceView()
        case .settings: SettingsView()
        }
    }
}
