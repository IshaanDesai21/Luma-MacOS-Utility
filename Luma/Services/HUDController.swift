import AppKit
import SwiftUI

/// Presents a small, native-looking heads-up display in the center of the
/// screen (used for microphone mute feedback), then fades it away.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(symbol: String, title: String, animationSpeed: Double = 1) {
        let panel = ensurePanel()
        panel.contentView = NSHostingView(rootView: HUDView(symbol: symbol, title: title))
        panel.setContentSize(NSSize(width: 172, height: 172))
        center(panel)

        dismissTask?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18 / max(animationSpeed, 0.1)
            panel.animator().alphaValue = 1
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.dismiss(animationSpeed: animationSpeed)
        }
    }

    private func dismiss(animationSpeed: Double) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3 / max(animationSpeed, 0.1)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 172, height: 172),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private func center(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let size = panel.frame.size
        let origin = CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + frame.height * 0.18
        )
        panel.setFrameOrigin(origin)
    }
}

private struct HUDView: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 172, height: 172)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }
}
