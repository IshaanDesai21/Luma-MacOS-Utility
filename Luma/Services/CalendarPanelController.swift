import AppKit
import SwiftUI

/// Shows a floating glass month-calendar panel near the top of the screen.
@MainActor
final class CalendarPanelController {
    private var panel: NSPanel?

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func show() {
        let panel = ensurePanel()
        panel.contentView = NSHostingView(rootView: MonthCalendarView(onClose: { [weak self] in self?.hide() }))
        panel.layoutIfNeeded()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 332, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let inset = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 12
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - inset
        )
        panel.setFrameOrigin(origin)
    }
}
