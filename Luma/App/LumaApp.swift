import SwiftUI

@main
struct LumaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(initialItem: appDelegate.model.settings.launchOnSettings ? .settings : .dynamicIsland)
                .environment(appDelegate.model)
                .environment(appDelegate.model.settings)
                .environment(appDelegate.model.spotify)
                .environment(appDelegate.model.nowPlaying)
                .environment(appDelegate.model.workspaceStore)
                .environment(appDelegate.model.appCatalog)
                .environment(appDelegate.model.moduleManager)
                .environment(appDelegate.model.islandModel)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
