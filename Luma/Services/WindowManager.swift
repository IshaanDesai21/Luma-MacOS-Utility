import AppKit
import SwiftUI
import Observation

/// Owns the Dynamic Island overlay window.
///
/// The panel is a fixed-size transparent canvas pinned to the top-center of the
/// screen. It NEVER animates or resizes — SwiftUI alone draws and animates the
/// island inside it, so window layout and view layout cannot fight (the source
/// of every past sizing glitch). Clicks pass through everywhere except the
/// island's own rect, which the container view hit-tests dynamically.
@MainActor
final class WindowManager {
    private var panel: NSPanel?
    private var container: IslandContainerView?
    private var model: DynamicIslandModel?

    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var collapseTask: Task<Void, Never>?
    private var optionDismissed = false

    /// Canvas size — big enough for the largest island at maximum scale plus
    /// shadow slack. Static so the window frame never has to change.
    private let canvasSize = CGSize(width: 640, height: 260)

    // MARK: - Lifecycle

    func show(model: DynamicIslandModel) {
        self.model = model
        if panel == nil {
            createPanel()
            installContent(model: model)
        }
        position()
        panel?.orderFrontRegardless()
        installMonitors()
        beginObserving()
        // Screen info can be stale at launch; settle once the run loop turns.
        Task { @MainActor [weak self] in
            self?.position()
            self?.panel?.orderFrontRegardless()
        }
    }

    func hide() {
        removeMonitors()
        collapseTask?.cancel()
        collapseTask = nil
        panel?.orderOut(nil)
    }

    // MARK: - Panel

    private func createPanel() {
        let panel = IslandPanel(
            contentRect: CGRect(origin: .zero, size: canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
    }

    private func installContent(model: DynamicIslandModel) {
        let container = IslandContainerView(frame: CGRect(origin: .zero, size: canvasSize))
        container.interactiveRect = { [weak self] in self?.islandRectInView() ?? .zero }
        container.onScroll = { [weak model] delta in model?.scrollVolume(by: delta) }

        let root = DynamicIslandView()
            .environment(model)
            .environment(model.spotify)
            .environment(model.settings)
            .ignoresSafeArea()
        let host = NSHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        panel?.contentView = container
        self.container = container
    }

    /// Pins the canvas to the top-center of the target screen (plus the user's
    /// horizontal offset). Called on screen/setting changes only — never as part
    /// of presentation changes, and never animated.
    private func position() {
        guard let panel, let model, let screen = targetScreen() else { return }
        model.topInset = topInset(for: screen)
        let x = screen.frame.midX - canvasSize.width / 2 + CGFloat(model.settings.islandHorizontalOffset)
        let y = screen.frame.maxY - canvasSize.height
        panel.setFrame(CGRect(x: x, y: y, width: canvasSize.width, height: canvasSize.height), display: true)
    }

    // MARK: - Geometry (single source shared by hit-testing and hover)

    /// The island's rect in the panel's view coordinates (origin bottom-left).
    private func islandRectInView() -> CGRect {
        guard let model else { return .zero }
        let layout = model.currentLayout
        return CGRect(
            x: (canvasSize.width - layout.width) / 2,
            y: canvasSize.height - model.topInset - layout.height,
            width: layout.width,
            height: layout.height
        )
    }

    /// Same rect in global screen coordinates (for hover monitors).
    private func islandRectOnScreen() -> CGRect {
        guard let panel else { return .zero }
        let local = islandRectInView()
        return CGRect(
            x: panel.frame.minX + local.minX,
            y: panel.frame.minY + local.minY,
            width: local.width,
            height: local.height
        )
    }

    /// Strip along the top of the screen around the notch that wakes the island.
    /// The user's activation-area setting scales how far it reaches.
    private func hoverZone() -> CGRect {
        guard let panel, let model else { return .zero }
        let factor = CGFloat(model.settings.islandActivationArea)
        let width = max(model.currentLayout.width + 60, 260) * factor
        let height = model.topInset + 8 + 10 * factor
        return CGRect(
            x: panel.frame.midX - width / 2,
            y: (targetScreen()?.frame.maxY ?? panel.frame.maxY) - height,
            width: width,
            height: height
        )
    }

    // MARK: - Hover + modifier monitoring

    private func installMonitors() {
        guard localMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateHover(at: NSEvent.mouseLocation)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover(at: NSEvent.mouseLocation) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event.modifierFlags) }
        }
    }

    private func removeMonitors() {
        [localMouseMonitor, globalMouseMonitor, localFlagsMonitor, globalFlagsMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
        localFlagsMonitor = nil
        globalFlagsMonitor = nil
    }

    private func updateHover(at point: CGPoint) {
        guard let model, !optionDismissed else { return }
        let over = hoverZone().contains(point) || islandRectOnScreen().insetBy(dx: -8, dy: -8).contains(point)

        if over {
            collapseTask?.cancel()
            collapseTask = nil
            if !model.isHovering { model.isHovering = true }
        } else if model.isHovering {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let self, !Task.isCancelled else { return }
            self.model?.isHovering = false
            self.collapseTask = nil
        }
    }

    /// Holding Option while over the island dismisses it so you can click
    /// through. Option elsewhere does nothing.
    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let point = NSEvent.mouseLocation
        let overIsland = hoverZone().contains(point) || islandRectOnScreen().contains(point)
        if flags.contains(.option), overIsland {
            setOptionDismissed(true)
        } else if !flags.contains(.option) {
            setOptionDismissed(false)
        }
    }

    private func setOptionDismissed(_ dismissed: Bool) {
        guard optionDismissed != dismissed else { return }
        optionDismissed = dismissed
        panel?.ignoresMouseEvents = dismissed
        panel?.animator().alphaValue = dismissed ? 0 : 1
    }

    // MARK: - Observation

    private func beginObserving() {
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.position() }
            }
        }
        observeSettings()
    }

    private func observeSettings() {
        withObservationTracking { [weak self] in
            _ = self?.model?.settings.islandHorizontalOffset
            _ = self?.model?.settings.islandVerticalOffset
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.position()
                self?.observeSettings()
            }
        }
    }

    // MARK: - Screen

    private func topInset(for screen: NSScreen) -> CGFloat {
        // Below the notch on notched Macs; just under the top edge otherwise.
        let base = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 4
        let offset = CGFloat(model?.settings.islandVerticalOffset ?? 0)
        return max(base - offset, 0)
    }

    private func targetScreen() -> NSScreen? {
        // NSScreen.main can be nil early in launch; always fall back to a real screen.
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    deinit {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
        if let globalFlagsMonitor { NSEvent.removeMonitor(globalFlagsMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}

/// A borderless panel that can still become key, so SwiftUI controls inside it
/// (play/pause, drag targets) receive clicks.
private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Content view for the canvas: passes clicks through except over the island,
/// so the invisible parts of the big fixed window never block the menu bar or
/// anything behind them.
final class IslandContainerView: NSView {
    var interactiveRect: () -> CGRect = { .zero }
    var onScroll: ((CGFloat) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinate space.
        let local = convert(point, from: superview)
        guard interactiveRect().insetBy(dx: -6, dy: -6).contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
        super.scrollWheel(with: event)
    }
}
