import SwiftUI
import Observation

/// Root object that owns the app's shared services, modules, and managers.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let spotify: SpotifyService
    let workspaceStore: WorkspaceStore
    let appCatalog: AppCatalog
    let monitor: SystemMonitor

    @ObservationIgnored let moduleServices: ModuleServices
    @ObservationIgnored let moduleManager: ModuleManager
    @ObservationIgnored let menuBarManager: MenuBarManager
    @ObservationIgnored let dynamicIslandManager: DynamicIslandManager
    @ObservationIgnored let dockClickWatcher = DockClickWatcher()
    @ObservationIgnored let nowPlaying: NowPlayingService
    @ObservationIgnored private var mediaKeyInterceptor: MediaKeyInterceptor?

    var islandModel: DynamicIslandModel { dynamicIslandManager.model }

    init() {
        let settings = AppSettings()
        let spotify = SpotifyService()
        let monitor = SystemMonitor()

        let services = ModuleServices(
            settings: settings,
            spotify: spotify,
            audio: AudioController(),
            microphone: MicrophoneController(),
            brightness: BrightnessController(),
            hud: HUDController(),
            monitor: monitor,
            timer: TimerService(),
            actions: SystemActions(),
            shelf: FileShelf(),
            inputSource: InputSourceController(),
            calendarPanel: CalendarPanelController(),
            downloads: DownloadsService(),
            clipboard: ClipboardService()
        )

        let moduleManager = ModuleManager(services: services)

        self.settings = settings
        self.spotify = spotify
        self.monitor = monitor
        self.workspaceStore = WorkspaceStore()
        self.appCatalog = AppCatalog()
        self.moduleServices = services
        self.moduleManager = moduleManager
        self.menuBarManager = MenuBarManager(moduleManager: moduleManager, settings: settings)
        let nowPlaying = NowPlayingService(spotify: spotify)
        self.nowPlaying = nowPlaying
        self.dynamicIslandManager = DynamicIslandManager(
            player: nowPlaying,
            settings: settings,
            shelf: services.shelf,
            audio: services.audio,
            brightness: services.brightness,
            monitor: monitor,
            downloads: services.downloads,
            moduleManager: moduleManager
        )
    }

    func start() {
        settings.applyAppearance()
        spotify.startMonitoring()
        nowPlaying.startMonitoring()
        monitor.start()
        moduleServices.downloads.start()
        moduleServices.clipboard.start()
        menuBarManager.install()
        dynamicIslandManager.install()
        registerHotkeys()
        observeHotkeys()
        observeDockClick()
        installMediaKeyInterceptor()
        // Any system volume change (keys, slider, AirPods) pops the island HUD.
        moduleServices.audio.startObservingSystemChanges { [weak self] in
            guard let self, self.settings.islandSystemHUD, self.settings.islandEnabled else { return }
            self.islandModel.flashVolume()
        }
    }

    /// Replaces the system volume/brightness bezel with the island readout.
    private func installMediaKeyInterceptor() {
        let interceptor = MediaKeyInterceptor(
            settings: settings,
            audio: moduleServices.audio,
            brightness: moduleServices.brightness,
            onVolume: { [weak self] in self?.islandModel.flashVolume() },
            onBrightness: { [weak self] in self?.islandModel.flashBrightness() }
        )
        mediaKeyInterceptor = interceptor
        observeMediaKeySetting()
    }

    private func observeMediaKeySetting() {
        mediaKeyInterceptor?.setEnabled(settings.islandSystemHUD && settings.islandEnabled)
        withObservationTracking {
            _ = settings.islandSystemHUD
            _ = settings.islandEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeMediaKeySetting() }
        }
    }

    private func observeDockClick() {
        dockClickWatcher.setEnabled(settings.dockClickToHide)
        withObservationTracking {
            _ = settings.dockClickToHide
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeDockClick() }
        }
    }

    func stop() {
        spotify.stopMonitoring()
        monitor.stop()
        dynamicIslandManager.stop()
        HotkeyCenter.shared.unregister(id: HotkeyID.islandHide)
        HotkeyCenter.shared.unregister(id: HotkeyID.micMute)
    }

    // MARK: - Hotkeys

    private enum HotkeyID {
        static let islandHide: UInt32 = 1
        static let micMute: UInt32 = 2
    }

    private func registerHotkeys() {
        HotkeyCenter.shared.register(id: HotkeyID.islandHide, shortcut: settings.islandHideShortcut) { [weak self] in
            self?.settings.islandEnabled.toggle()
        }
        HotkeyCenter.shared.register(id: HotkeyID.micMute, shortcut: settings.micMuteShortcut) { [weak self] in
            guard let self else { return }
            let muted = self.moduleServices.microphone.toggle()
            self.moduleServices.hud.show(
                symbol: muted ? "mic.slash.fill" : "mic.fill",
                title: muted ? "Mic Muted" : "Mic Unmuted",
                animationSpeed: self.settings.animationSpeed
            )
        }
    }

    private func observeHotkeys() {
        withObservationTracking {
            _ = settings.islandHideShortcut
            _ = settings.micMuteShortcut
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.registerHotkeys()
                self?.observeHotkeys()
            }
        }
    }
}
