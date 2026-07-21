import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selection: SidebarItem?

    init(initialItem: SidebarItem = .dynamicIsland) {
        _selection = State(initialValue: initialItem)
    }

    var body: some View {
        content
            .sheet(isPresented: Binding(
                get: { !settings.hasCompletedOnboarding },
                set: { if !$0 { settings.hasCompletedOnboarding = true } }
            )) {
                OnboardingView()
            }
    }

    private var content: some View {
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
