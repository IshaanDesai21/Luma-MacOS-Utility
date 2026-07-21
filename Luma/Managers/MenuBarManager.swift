import AppKit
import SwiftUI
import Observation

/// Manages the macOS menu bar. In individual mode every enabled menu-bar module
/// gets its own status item; in collapsed mode a single Luma item opens a
/// popover containing them all.
@MainActor
final class MenuBarManager {
    private let moduleManager: ModuleManager
    private let settings: AppSettings

    private var controllers: [MenuBarItemController] = []
    private var sizingTask: Task<Void, Never>?

    init(moduleManager: ModuleManager, settings: AppSettings) {
        self.moduleManager = moduleManager
        self.settings = settings
    }

    func install() {
        rebuild()
        observe()
        startSizing()
    }

    /// Live chips (CPU %, clock…) change width as their text changes, so keep
    /// each item's length in sync with its content.
    private func startSizing() {
        guard sizingTask == nil else { return }
        sizingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.controllers.forEach { $0.updateLength() }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func observe() {
        withObservationTracking { [weak self] in
            _ = self?.moduleManager.revision
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuild()
                self?.observe()
            }
        }
    }

    private func rebuild() {
        controllers.forEach { $0.remove() }
        controllers.removeAll()

        let modules = moduleManager.modules(for: .menuBar)
        guard !modules.isEmpty else { return }

        if moduleManager.collapseMenuBar {
            buildCollapsed()
        } else {
            buildIndividual(modules)
        }
    }

    private func buildIndividual(_ modules: [Module]) {
        for module in modules {
            let compact = moduleManager.isCompact(module)
            let label = module.menuBarView(compact: compact)
                ?? AnyView(MenuBarChip(systemImage: module.icon, text: ""))
            let inner = module.menuBarPopover() ?? module.menuBarView() ?? AnyView(EmptyView())
            let content = module.menuBarPopoverUsesChrome
                ? popoverContent(title: module.name) { inner }
                : AnyView(inner)
            controllers.append(MenuBarItemController(
                label: label,
                content: content,
                width: 260,
                directAction: module.menuBarAction()
            ))
        }
    }

    private func buildCollapsed() {
        let icon = AnyView(
            Image(systemName: "moon.stars")
                .font(.system(size: 14, weight: .medium))
        )
        let content = AnyView(
            MenuBarPopoverView(moduleManager: moduleManager, settings: settings)
        )
        controllers.append(MenuBarItemController(label: icon, content: content, width: 300))
    }

    private func popoverContent(title: String, @ViewBuilder body: () -> AnyView) -> AnyView {
        let inner = body()
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                inner
            }
            .padding(16)
            .frame(width: 260, alignment: .leading)
            .background(settings.glassMaterial)
        )
    }
}

/// Wraps a single `NSStatusItem` and its transient popover.
@MainActor
final class MenuBarItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private weak var hostView: NSHostingView<AnyView>?
    private let horizontalPadding: CGFloat = 12
    private let directAction: (() -> Void)?

    init(label: AnyView, content: AnyView, width: CGFloat, directAction: (() -> Void)? = nil) {
        self.directAction = directAction
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            // Disable hit testing on the SwiftUI layer so clicks reach the
            // status-item button and toggle the popover.
            let host = NSHostingView(rootView: AnyView(label.allowsHitTesting(false)))
            host.sizingOptions = [.intrinsicContentSize]
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            // Center the content; the item's overall width is set explicitly via
            // `updateLength()` so nothing gets clipped as the text grows.
            NSLayoutConstraint.activate([
                host.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                host.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            hostView = host
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = true
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller

        updateLength()
    }

    /// Sizes the status item to fit its current content width.
    func updateLength() {
        guard let host = hostView else { return }
        host.layoutSubtreeIfNeeded()
        let width = host.fittingSize.width
        guard width > 0 else { return }
        statusItem.length = width + horizontalPadding
    }

    @objc private func togglePopover() {
        if let directAction {
            directAction()
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
