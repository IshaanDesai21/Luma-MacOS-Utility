import Foundation
import Observation

/// Coordinates the floating Dynamic Island overlay. Currently renders the
/// Spotify now-playing card; the module system lets other modules opt into the
/// island in future without touching the window plumbing.
@MainActor
final class DynamicIslandManager {
    let model: DynamicIslandModel

    @ObservationIgnored private let windowManager: WindowManager
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let moduleManager: ModuleManager

    init(spotify: SpotifyService, settings: AppSettings, shelf: FileShelf, moduleManager: ModuleManager) {
        self.model = DynamicIslandModel(spotify: spotify, settings: settings, shelf: shelf)
        self.windowManager = WindowManager()
        self.settings = settings
        self.moduleManager = moduleManager
    }

    func install() {
        apply()
        observe()
    }

    func stop() {
        windowManager.hide()
    }

    /// Modules that have opted into the Dynamic Island location.
    var islandModules: [Module] {
        moduleManager.modules(for: .dynamicIsland)
    }

    private func observe() {
        withObservationTracking { [weak self] in
            _ = self?.settings.islandEnabled
            _ = self?.moduleManager.revision
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.apply()
                self?.observe()
            }
        }
    }

    private func apply() {
        if settings.islandEnabled {
            windowManager.show(model: model)
        } else {
            windowManager.hide()
        }
    }
}
