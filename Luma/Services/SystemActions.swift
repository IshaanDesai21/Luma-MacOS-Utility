import AppKit

/// Best-effort wrappers around native system actions used by modules.
@MainActor
struct SystemActions {
    func showEmojiPicker() {
        NSApp.orderFrontCharacterPalette(nil)
    }

    func openMissionControl() {
        launchApp(bundleID: "com.apple.exposelauncher",
                  fallbackPath: "/System/Applications/Mission Control.app")
    }

    func openLaunchpad() {
        launchApp(bundleID: "com.apple.launchpad.launcher",
                  fallbackPath: "/System/Applications/Launchpad.app")
    }

    func lockScreen() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    func sleepNow() {
        run("/usr/bin/pmset", ["sleepnow"])
    }

    func openFocusSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func launchApp(bundleID: String, fallbackPath: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let url = URL(fileURLWithPath: fallbackPath)
        if FileManager.default.fileExists(atPath: fallbackPath) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func run(_ launchPath: String, _ arguments: [String]) {
        Task { try? await ProcessRunner.run(launchPath, arguments: arguments, allowFailure: true) }
    }
}
