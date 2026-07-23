import SwiftUI
import Observation
import ApplicationServices

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
    @ObservationIgnored private(set) var mediaKeyInterceptor: MediaKeyInterceptor?

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
        let nowPlaying = NowPlayingService()
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
        observeAppActivation()
        // Any system volume change (keys, slider, AirPods) pops the island HUD.
        moduleServices.audio.startObservingSystemChanges { [weak self] in
            guard let self, self.settings.islandSystemHUD, self.settings.islandEnabled else { return }
            self.islandModel.flashVolume()
        }
        // Same for brightness, regardless of how it was changed.
        moduleServices.brightness.startObservingSystemChanges { [weak self] in
            guard let self, self.settings.islandSystemHUD, self.settings.islandEnabled else { return }
            self.islandModel.flashBrightness()
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

    // MARK: - Accessibility

    @ObservationIgnored private var didBecomeActiveObserver: NSObjectProtocol?
    @ObservationIgnored private var prevHUDWanted = false
    @ObservationIgnored private var prevDockWanted = false

    /// Prompts for Accessibility only when it's actually missing. Called only on
    /// an explicit user enable, so it never nags on launch or when granted.
    private func promptAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// The event taps can't be created until Accessibility is granted. When the
    /// user grants it in System Settings and returns to Luma, re-attempt install
    /// immediately instead of waiting on the background retry — no prompt.
    private func observeAppActivation() {
        guard didBecomeActiveObserver == nil else { return }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.mediaKeyInterceptor?.setEnabled(self.settings.islandSystemHUD && self.settings.islandEnabled)
                self.dockClickWatcher.setEnabled(self.settings.dockClickToHide)
            }
        }
    }

    private func observeMediaKeySetting() {
        let wanted = settings.islandSystemHUD && settings.islandEnabled
        // Prompt only when the user just turned it on (off -> on), not on launch.
        if wanted && !prevHUDWanted && didStartHUDObserving { promptAccessibility() }
        prevHUDWanted = wanted
        didStartHUDObserving = true
        mediaKeyInterceptor?.setEnabled(wanted)
        withObservationTracking {
            _ = settings.islandSystemHUD
            _ = settings.islandEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeMediaKeySetting() }
        }
    }
    @ObservationIgnored private var didStartHUDObserving = false

    private func observeDockClick() {
        let wanted = settings.dockClickToHide
        if wanted && !prevDockWanted && didStartDockObserving { promptAccessibility() }
        prevDockWanted = wanted
        didStartDockObserving = true
        dockClickWatcher.setEnabled(wanted)
        withObservationTracking {
            _ = settings.dockClickToHide
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeDockClick() }
        }
    }
    @ObservationIgnored private var didStartDockObserving = false

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
