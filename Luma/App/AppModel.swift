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
        self.dynamicIslandManager = DynamicIslandManager(
            spotify: spotify,
            settings: settings,
            shelf: services.shelf,
            moduleManager: moduleManager
        )
    }

    func start() {
        settings.applyAppearance()
        spotify.startMonitoring()
        monitor.start()
        moduleServices.downloads.start()
        moduleServices.clipboard.start()
        menuBarManager.install()
        dynamicIslandManager.install()
        registerHotkeys()
        observeHotkeys()
        observeDockClick()
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
