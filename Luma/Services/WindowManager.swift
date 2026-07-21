import AppKit
import SwiftUI
import Observation

/// Owns the floating Dynamic Island `NSPanel`.
///
/// The panel is sized to the island itself (no dead click-box), accepts file
/// drops, and animates its frame while SwiftUI crossfades the contents.
@MainActor
final class WindowManager {
    private var panel: NSPanel?
    private var model: DynamicIslandModel?

    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var collapseTask: Task<Void, Never>?
    private var hoverZone: CGRect = .zero
    private var commandDismissed = false

    private let margin: CGFloat = 16

    // MARK: - Lifecycle

    func show(model: DynamicIslandModel) {
        self.model = model
        if panel == nil {
            createPanel()
            installContent(model: model)
        }
        panel?.orderFrontRegardless()
        installMonitors()
        beginObserving()
        layout(animated: false)
        // Re-run once the run loop settles, in case screen info wasn't ready yet.
        Task { @MainActor [weak self] in
            self?.panel?.orderFrontRegardless()
            self?.layout(animated: false)
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
            contentRect: CGRect(x: 0, y: 0, width: 160, height: 60),
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
        // The panel sits in the notch / menu-bar band; opt out of safe areas so
        // insets can't push or squash the island's layout there.
        let root = DynamicIslandView()
            .environment(model)
            .environment(model.spotify)
            .environment(model.settings)
            .ignoresSafeArea()
        let host = NSHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        host.safeAreaRegions = []
        panel?.contentView = host
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
        guard let model, !commandDismissed else { return }
        let overZone = hoverZone.contains(point)
        let overPanel = model.presentation != .hidden && (panel?.frame.contains(point) ?? false)

        if overZone || overPanel {
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
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            self.model?.isHovering = false
            self.collapseTask = nil
        }
    }

    /// Holding Option while over the notch/island dismisses it so you can click
    /// through. Option elsewhere does nothing.
    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let point = NSEvent.mouseLocation
        let overNotch = hoverZone.contains(point) || (panel?.frame.contains(point) ?? false)
        if flags.contains(.option), overNotch {
            setCommandDismissed(true)
        } else if !flags.contains(.option) {
            setCommandDismissed(false)
        }
    }

    private func setCommandDismissed(_ dismissed: Bool) {
        guard commandDismissed != dismissed else { return }
        commandDismissed = dismissed
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
                MainActor.assumeIsolated { self?.layout(animated: true) }
            }
        }
        observeState()
    }

    private func observeState() {
        withObservationTracking { [weak self] in
            _ = self?.model?.currentMetrics
            _ = self?.model?.settings.glassIntensity
            _ = self?.model?.settings.islandScale
            _ = self?.model?.settings.islandVerticalOffset
            _ = self?.model?.settings.islandHorizontalOffset
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.layout(animated: true)
                self?.observeState()
            }
        }
    }

    // MARK: - Layout

    private func layout(animated: Bool) {
        guard let panel, let model, let screen = targetScreen() else { return }
        model.topInset = topInset(for: screen)
        hoverZone = topHoverZone(on: screen)

        let scale = CGFloat(model.settings.islandScale)
        let metrics = model.currentMetrics
        let width = metrics.width * scale + margin * 2
        let height = metrics.height * scale + margin * 2
        let islandTop = screen.frame.maxY - model.topInset
        let horizontalOffset = CGFloat(model.settings.islandHorizontalOffset)
        let frame = CGRect(
            x: screen.frame.midX - width / 2 + horizontalOffset,
            y: islandTop + margin - height,
            width: width,
            height: height
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = model.settings.islandAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func topHoverZone(on screen: NSScreen) -> CGRect {
        let width = max(notchWidth(of: screen) + 90, 240)
        let inset = topInset(for: screen)
        let height = inset + 12
        let offset = CGFloat(model?.settings.islandHorizontalOffset ?? 0)
        return CGRect(x: screen.frame.midX - width / 2 + offset, y: screen.frame.maxY - height, width: width, height: height)
    }

    private func topInset(for screen: NSScreen) -> CGFloat {
        // Below the notch on notched Macs; near the top otherwise. The user
        // offset raises it further toward the top.
        let base = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 6
        let offset = CGFloat(model?.settings.islandVerticalOffset ?? 0)
        return max(base - offset, 0)
    }

    private func notchWidth(of screen: NSScreen) -> CGFloat {
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        guard left > 0, right > 0 else { return 200 }
        return max(screen.frame.width - left - right, 0)
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
