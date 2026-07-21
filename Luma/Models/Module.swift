import SwiftUI
import AppKit

/// Shared services handed to every module so modules stay free of singletons.
@MainActor
final class ModuleServices {
    let settings: AppSettings
    let spotify: SpotifyService
    let audio: AudioController
    let microphone: MicrophoneController
    let brightness: BrightnessController
    let hud: HUDController
    let monitor: SystemMonitor
    let timer: TimerService
    let actions: SystemActions
    let shelf: FileShelf
    let inputSource: InputSourceController
    let calendarPanel: CalendarPanelController
    let downloads: DownloadsService
    let clipboard: ClipboardService

    init(
        settings: AppSettings,
        spotify: SpotifyService,
        audio: AudioController,
        microphone: MicrophoneController,
        brightness: BrightnessController,
        hud: HUDController,
        monitor: SystemMonitor,
        timer: TimerService,
        actions: SystemActions,
        shelf: FileShelf,
        inputSource: InputSourceController,
        calendarPanel: CalendarPanelController,
        downloads: DownloadsService,
        clipboard: ClipboardService
    ) {
        self.settings = settings
        self.spotify = spotify
        self.audio = audio
        self.microphone = microphone
        self.brightness = brightness
        self.hud = hud
        self.monitor = monitor
        self.timer = timer
        self.actions = actions
        self.shelf = shelf
        self.inputSource = inputSource
        self.calendarPanel = calendarPanel
        self.downloads = downloads
        self.clipboard = clipboard
    }
}

/// A single self-contained utility that can surface itself in one or more
/// locations. Adding a utility means creating one `Module` and registering it
/// in ``ModuleManager`` — no switch statements elsewhere.
@MainActor
protocol Module: AnyObject {
    var id: String { get }
    var name: String { get }
    var icon: String { get }
    var supportedLocations: Set<ModuleLocation> { get }

    func sidebarView() -> AnyView?
    func menuBarView() -> AnyView?
    /// A space-saving menu-bar representation (typically icon-only). Defaults to
    /// the full ``menuBarView()``.
    func menuBarView(compact: Bool) -> AnyView?
    func menuBarPopover() -> AnyView?
    /// When false, the popover shows the module's view directly without the
    /// generic titled chrome (used by views that style themselves, e.g. Calendar).
    var menuBarPopoverUsesChrome: Bool { get }
    /// If non-nil, clicking the menu-bar item runs this instead of opening a popover.
    func menuBarAction() -> (() -> Void)?
    func dynamicIslandView() -> AnyView?
}

extension Module {
    func sidebarView() -> AnyView? { nil }
    func menuBarView() -> AnyView? { nil }
    /// Default compact form is icon-only, which saves the most menu-bar space.
    /// Modules with a stateful glyph (battery level, mic mute) override this.
    func menuBarView(compact: Bool) -> AnyView? {
        compact ? AnyView(MenuBarChip(systemImage: icon, text: "")) : menuBarView()
    }
    func menuBarPopover() -> AnyView? { menuBarView() }
    var menuBarPopoverUsesChrome: Bool { true }
    func menuBarAction() -> (() -> Void)? { nil }
    func dynamicIslandView() -> AnyView? { nil }
}
