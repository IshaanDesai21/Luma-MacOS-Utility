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

    init(
        player: NowPlayingService,
        settings: AppSettings,
        shelf: FileShelf,
        audio: AudioController,
        brightness: BrightnessController,
        monitor: SystemMonitor,
        downloads: DownloadsService,
        moduleManager: ModuleManager
    ) {
        self.model = DynamicIslandModel(
            player: player,
            settings: settings,
            shelf: shelf,
            audio: audio,
            brightness: brightness,
            monitor: monitor,
            downloads: downloads
        )
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
            model.sensors.start()
        } else {
            model.sensors.stop()
            windowManager.hide()
        }
    }
}
