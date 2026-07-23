import AppKit
import ApplicationServices
import Observation

/// Hides the active app when you click its Dock icon, so it disappears and
/// whatever was behind it comes forward (click the icon again to bring it back).
///
/// Uses a CGEvent tap that *consumes* the click before the Dock sees it — the
/// only reliable way: with a passive monitor the Dock also handles the same
/// click and immediately re-activates the app, undoing the hide. Clicks on
/// anything other than the active app's tile (and all modifier-clicks) pass
/// through untouched.
@MainActor
@Observable
final class DockClickWatcher {
    private(set) var isEnabled = false

    /// Live diagnostic shown in Dock settings so failures aren't silent.
    private(set) var status = "Off"

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var swallowNextMouseUp = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    // MARK: - Lifecycle

    private func start() {
        guard tap == nil else { return }
        // Prompting is centralized in AppModel (once per launch); just try to
        // install and keep retrying quietly until Accessibility is granted.
        if !installTap() {
            scheduleRetry()
        }
    }

    private func stop() {
        retryTask?.cancel()
        retryTask = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
        swallowNextMouseUp = false
        isEnabled = false
        status = "Off"
    }

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let watcher = Unmanaged<DockClickWatcher>.fromOpaque(info).takeUnretainedValue()
                // The tap's run-loop source lives on the main run loop.
                return MainActor.assumeIsolated { watcher.handle(type: type, event: event) }
            },
            userInfo: info
        ) else {
            status = AXIsProcessTrusted()
                ? "Couldn’t start click interceptor — retrying…"
                : "Waiting for Accessibility permission…"
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isEnabled = true
        status = "Active — click your app’s Dock icon to hide it"
        return true
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, self.tap == nil else { return }
            if !self.installTap() { self.scheduleRetry() }
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system disables slow/paused taps; turn ours back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)

        case .leftMouseUp:
            // Swallow the matching mouse-up of a click we consumed, otherwise the
            // Dock would treat the orphaned up as the end of a click.
            if swallowNextMouseUp {
                swallowNextMouseUp = false
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            // Leave modifier-clicks alone (⌘-click reveals in Finder, ⌥-click
            // hides others, ctrl-click menus…).
            let flags = event.flags
            if flags.contains(.maskCommand) || flags.contains(.maskAlternate)
                || flags.contains(.maskControl) || flags.contains(.maskShift) {
                return Unmanaged.passUnretained(event)
            }
            guard let front = frontAppIfClickOnItsTile(at: event.location) else {
                return Unmanaged.passUnretained(event)
            }
            // Consume the click entirely — the Dock never sees it, so nothing
            // can re-activate the app — then hide.
            swallowNextMouseUp = true
            let name = front.localizedName ?? "app"
            status = front.hide() ? "Hid \(name) ✓" : "Tried to hide \(name) but macOS refused"
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// If the click landed on the Dock tile of the frontmost regular app,
    /// returns that app; otherwise nil. `location` is in top-left-origin global
    /// coordinates, which is what the AX hit test expects. Updates `status` at
    /// each decision point so failures are visible in Dock settings.
    private func frontAppIfClickOnItsTile(at location: CGPoint) -> NSRunningApplication? {
        guard AXIsProcessTrusted() else {
            status = "Accessibility permission missing"
            return nil
        }
        guard let dockPID = dockProcessID() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(location.x), Float(location.y), &element) == .success,
              let element else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid == dockPID else { return nil }

        guard let front = NSWorkspace.shared.frontmostApplication,
              front.activationPolicy == .regular else {
            status = "Dock click seen, but no regular app is frontmost"
            return nil
        }
        let frontName = front.localizedName ?? "?"

        // Prefer an exact bundle-URL match (immune to renamed/localized tiles);
        // fall back to the tile title.
        if let url = dockItemURL(from: element), let frontURL = front.bundleURL {
            if url.standardizedFileURL == frontURL.standardizedFileURL { return front }
            status = "Clicked \(url.deletingPathExtension().lastPathComponent) — not the active app (\(frontName))"
            return nil
        }
        if let title = dockItemTitle(from: element) {
            if title == frontName { return front }
            status = "Clicked “\(title)” — not the active app (\(frontName))"
            return nil
        }
        status = "Dock click seen, but couldn’t identify the tile"
        return nil
    }

    // MARK: - AX helpers

    /// Walks up a few parents since a click can land on a child element (icon
    /// image, running indicator) that carries no attributes itself.
    private func dockItemURL(from element: AXUIElement) -> URL? {
        var current: AXUIElement? = element
        for _ in 0..<4 {
            guard let node = current else { break }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXURLAttribute as CFString, &value) == .success,
               let url = value as? URL {
                return url
            }
            current = copyElement(node, kAXParentAttribute)
        }
        return nil
    }

    private func dockItemTitle(from element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for _ in 0..<4 {
            guard let node = current else { break }
            if let title = copyString(node, kAXTitleAttribute), !title.isEmpty {
                return title
            }
            current = copyElement(node, kAXParentAttribute)
        }
        return nil
    }

    private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func dockProcessID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }
}
