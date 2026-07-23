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

    /// Canvas size, big enough for the largest island (wide calendar card at
    /// max scale) plus shadow slack. Static so panel frames never have to change.
    private let canvasSize = CGSize(width: 960, height: 320)

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

        let notchStyle = model.settings.islandStyle == .notch

        // Publish the notch dimensions from the notched display (used by the
        // "part of the notch" style so the tab matches it exactly).
        if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            model.notchSize = Self.notchSize(for: notched)
        } else {
            model.notchSize = .zero
        }

        // The island's position inside the canvas is shared by every panel;
        // per-screen differences (notch vs none) are absorbed by each panel's
        // y-origin below. In notch style the island is flush with the very top.
        let referenceInset = notchStyle ? 0 : (screens.map { Self.baseInset(for: $0) }.max() ?? 32)
        model.topInset = max(referenceInset - CGFloat(model.settings.islandVerticalOffset), 0)

        for screen in screens {
            let baseInset = notchStyle ? 0 : Self.baseInset(for: screen)
            let inset = max(baseInset - CGFloat(model.settings.islandVerticalOffset), 0)
            let panel = makePanel()
            let container = makeContainer(model: model)
            panel.contentView = container

            let x = screen.frame.midX - canvasSize.width / 2 + CGFloat(model.settings.islandHorizontalOffset)
            // Shift so the island's top lands exactly `inset` below THIS
            // screen's top even though the in-canvas layout uses the shared inset.
            let y = screen.frame.maxY - inset - canvasSize.height + model.topInset
            panel.setFrame(CGRect(x: x, y: y, width: canvasSize.width, height: canvasSize.height), display: true)
            panel.alphaValue = optionDismissed ? 0 : 1
            // Pass-through by default: the big canvas must NEVER eat clicks.
            // `updateInteractivity` flips this off only while the cursor is
            // actually over the island itself.
            panel.ignoresMouseEvents = true
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
        // Never take key focus for plain clicks (buttons/sliders work without
        // it) — becoming key was re-rendering the glass in a "focused" style.
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    private func makeContainer(model: DynamicIslandModel) -> IslandContainerView {
        let container = IslandContainerView(frame: CGRect(origin: .zero, size: canvasSize))
        container.interactiveRect = { [weak self] in self?.islandRectInCanvas() ?? .zero }
        // Scroll routing: over the expanded card with the calendar shown, page
        // through dates; over the resting pod, change the volume.
        container.scrollMode = { [weak model] in
            guard let model else { return .none }
            if model.presentation == .expanded && model.settings.islandShowCalendar { return .calendar }
            if model.presentation == .peek { return .volume }
            return .none
        }
        container.onVolumeScroll = { [weak model] delta in model?.scrollVolume(by: delta) }
        container.onCalendarStep = { [weak model] step in
            guard let model else { return }
            withAnimation(.smooth(duration: 0.34)) { model.calendar.shift(days: step) }
        }

        let root = DynamicIslandView()
            .environment(model)
            .environment(model.player)
            .environment(model.settings)
            // Pin the rendering to "active" so glass/material never shifts when
            // the panel becomes or resigns the key window (click vs idle).
            .environment(\.controlActiveState, .active)
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
        // Also watch drags so file drops flip the panel interactive in time.
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
            self?.updateHover(at: NSEvent.mouseLocation)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] _ in
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
        updateInteractivity(at: point)
        guard let model, !optionDismissed else { return }
        if isOverIsland(point) {
            collapseTask?.cancel()
            collapseTask = nil
            if !model.isHovering { model.isHovering = true }
        } else if model.isHovering {
            scheduleCollapse()
        }
    }

    /// The canvas windows pass every event through except when the cursor is
    /// over the island itself. Returning nil from hitTest is not enough: the
    /// window server still routes clicks to the topmost window, so the flag
    /// must be flipped ahead of the click.
    private func updateInteractivity(at point: CGPoint) {
        let local = islandRectInCanvas()
        for entry in entries {
            let rect = CGRect(
                x: entry.panel.frame.minX + local.minX,
                y: entry.panel.frame.minY + local.minY,
                width: local.width,
                height: local.height
            ).insetBy(dx: -8, dy: -8)
            let interactive = !optionDismissed && rect.contains(point)
            if entry.panel.ignoresMouseEvents == interactive {
                entry.panel.ignoresMouseEvents = !interactive
            }
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
            entry.panel.animator().alphaValue = dismissed ? 0 : 1
        }
        updateInteractivity(at: NSEvent.mouseLocation)
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
            _ = self?.model?.settings.islandStyle
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

    /// The physical notch's size, or `.zero` if the display has none.
    private static func notchSize(for screen: NSScreen) -> CGSize {
        let top = screen.safeAreaInsets.top
        guard top > 0 else { return .zero }
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        guard left > 0, right > 0 else { return CGSize(width: 200, height: top) }
        let width = max(screen.frame.width - left - right, 0)
        return CGSize(width: width, height: top)
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
    enum ScrollMode { case volume, calendar, none }

    var interactiveRect: () -> CGRect = { .zero }
    var scrollMode: () -> ScrollMode = { .none }
    var onVolumeScroll: ((CGFloat) -> Void)?
    var onCalendarStep: ((Int) -> Void)?

    // Larger threshold = slower, one-day-at-a-time calendar paging.
    private var calendarAccumulator: CGFloat = 0
    private let pointsPerDay: CGFloat = 55

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinate space.
        let local = convert(point, from: superview)
        guard interactiveRect().insetBy(dx: -6, dy: -6).contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        switch scrollMode() {
        case .volume:
            onVolumeScroll?(event.scrollingDeltaY)
        case .calendar:
            let horizontal = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            let delta = horizontal ? event.scrollingDeltaX : -event.scrollingDeltaY
            calendarAccumulator += delta
            if abs(calendarAccumulator) >= pointsPerDay {
                onCalendarStep?(calendarAccumulator > 0 ? 1 : -1)
                calendarAccumulator = 0
            }
        case .none:
            break
        }
    }
}
