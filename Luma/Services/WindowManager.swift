import AppKit
import SwiftUI
import Observation

/// Owns the Dynamic Island overlay windows, one per display.
///
/// Each panel is a fixed-size transparent canvas pinned to the top-center of
/// its screen. Panels NEVER animate or resize; SwiftUI alone draws and animates
/// the island inside them, so window layout and view layout cannot fight.
/// Clicks pass through everywhere except the island's own rect, which the
/// container view hit-tests dynamically.
@MainActor
final class WindowManager {
    private struct Entry {
        let panel: NSPanel
        let container: IslandContainerView
        let screenFrame: CGRect
        let screenInset: CGFloat
    }

    private var entries: [Entry] = []
    private var model: DynamicIslandModel?

    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var collapseTask: Task<Void, Never>?
    private var optionDismissed = false

    /// Canvas size, big enough for the largest island at maximum scale plus
    /// shadow slack. Static so panel frames never have to change.
    private let canvasSize = CGSize(width: 640, height: 260)

    // MARK: - Lifecycle

    func show(model: DynamicIslandModel) {
        self.model = model
        rebuildPanels()
        installMonitors()
        beginObserving()
        // Screen info can be stale at launch; settle once the run loop turns.
        Task { @MainActor [weak self] in
            self?.rebuildPanels()
        }
    }

    func hide() {
        removeMonitors()
        collapseTask?.cancel()
        collapseTask = nil
        tearDownPanels()
    }

    // MARK: - Panels (one per screen)

    private func rebuildPanels() {
        guard let model else { return }
        tearDownPanels()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        // The island's position inside the canvas is shared by every panel;
        // per-screen differences (notch vs none) are absorbed by each panel's
        // y-origin below.
        let referenceInset = screens.map { Self.baseInset(for: $0) }.max() ?? 32
        model.topInset = max(referenceInset - CGFloat(model.settings.islandVerticalOffset), 0)

        for screen in screens {
            let inset = max(Self.baseInset(for: screen) - CGFloat(model.settings.islandVerticalOffset), 0)
            let panel = makePanel()
            let container = makeContainer(model: model)
            panel.contentView = container

            let x = screen.frame.midX - canvasSize.width / 2 + CGFloat(model.settings.islandHorizontalOffset)
            // Shift so the island's top lands exactly `inset` below THIS
            // screen's top even though the in-canvas layout uses the shared inset.
            let y = screen.frame.maxY - inset - canvasSize.height + model.topInset
            panel.setFrame(CGRect(x: x, y: y, width: canvasSize.width, height: canvasSize.height), display: true)
            panel.alphaValue = optionDismissed ? 0 : 1
            panel.ignoresMouseEvents = optionDismissed
            panel.orderFrontRegardless()

            entries.append(Entry(panel: panel, container: container, screenFrame: screen.frame, screenInset: inset))
        }
    }

    private func tearDownPanels() {
        entries.forEach { $0.panel.orderOut(nil) }
        entries.removeAll()
    }

    private func makePanel() -> NSPanel {
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
        return panel
    }

    private func makeContainer(model: DynamicIslandModel) -> IslandContainerView {
        let container = IslandContainerView(frame: CGRect(origin: .zero, size: canvasSize))
        container.interactiveRect = { [weak self] in self?.islandRectInCanvas() ?? .zero }
        container.onScroll = { [weak model] delta in model?.scrollVolume(by: delta) }

        let root = DynamicIslandView()
            .environment(model)
            .environment(model.player)
            .environment(model.settings)
            .ignoresSafeArea()
        let host = NSHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
    }

    // MARK: - Geometry (single source shared by hit-testing and hover)

    /// The island's rect in canvas coordinates (origin bottom-left) — the same
    /// for every panel, since panels compensate per-screen via their origin.
    private func islandRectInCanvas() -> CGRect {
        guard let model else { return .zero }
        let layout = model.currentLayout
        return CGRect(
            x: (canvasSize.width - layout.width) / 2,
            y: canvasSize.height - model.topInset - layout.height,
            width: layout.width,
            height: layout.height
        )
    }

    private func islandRects() -> [CGRect] {
        let local = islandRectInCanvas()
        return entries.map { entry in
            CGRect(
                x: entry.panel.frame.minX + local.minX,
                y: entry.panel.frame.minY + local.minY,
                width: local.width,
                height: local.height
            )
        }
    }

    /// Hover strips along the top of each screen around the island.
    private func hoverZones() -> [CGRect] {
        guard let model else { return [] }
        let factor = CGFloat(model.settings.islandActivationArea)
        let width = max(model.currentLayout.width + 60, 260) * factor
        return entries.map { entry in
            let height = entry.screenInset + 8 + 10 * factor
            return CGRect(
                x: entry.panel.frame.midX - width / 2,
                y: entry.screenFrame.maxY - height,
                width: width,
                height: height
            )
        }
    }

    private func isOverIsland(_ point: CGPoint) -> Bool {
        hoverZones().contains { $0.contains(point) }
            || islandRects().contains { $0.insetBy(dx: -8, dy: -8).contains(point) }
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
        if isOverIsland(point) {
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
        if flags.contains(.option), isOverIsland(point) {
            setOptionDismissed(true)
        } else if !flags.contains(.option) {
            setOptionDismissed(false)
        }
    }

    private func setOptionDismissed(_ dismissed: Bool) {
        guard optionDismissed != dismissed else { return }
        optionDismissed = dismissed
        for entry in entries {
            entry.panel.ignoresMouseEvents = dismissed
            entry.panel.animator().alphaValue = dismissed ? 0 : 1
        }
    }

    // MARK: - Observation

    private func beginObserving() {
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildPanels() }
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
                self?.rebuildPanels()
                self?.observeSettings()
            }
        }
    }

    // MARK: - Screen

    /// Below the notch on notched displays; just under the top edge otherwise.
    private static func baseInset(for screen: NSScreen) -> CGFloat {
        screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 4
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

/// Content view for a canvas: passes clicks through except over the island, so
/// the invisible parts of the big fixed window never block the menu bar or
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
