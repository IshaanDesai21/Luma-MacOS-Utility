import AppKit
import Observation

/// Intercepts the keyboard's volume and brightness keys so the island can show
/// its own elegant readout instead of the system's square bezel. The keys are
/// consumed (macOS never draws its HUD) and the adjustment is performed by
/// Luma. If interception is unavailable (no Accessibility) or an adjustment
/// can't be made (e.g. brightness on some external displays, no output
/// device), the key passes through untouched so nothing ever breaks.
///
/// Permissions: an *active* CGEvent tap (`.defaultTap`, required to consume
/// events) is gated by the Accessibility TCC grant - System Settings > Privacy
/// & Security > Accessibility. No entitlements are involved: the app is not
/// sandboxed, hardened runtime is fine, and listen-only Input Monitoring is
/// NOT sufficient because it cannot swallow the event (the bezel would still
/// appear). The prompt is requested when the feature is enabled; until the
/// user grants it, a retry loop keeps trying and the keys behave natively.
///
/// Everything here is public API: `CGEvent.tapCreate`, `NSEvent(cgEvent:)`
/// parsing of `NX_SYSDEFINED` (type 14, subtype 8) media-key events, and
/// CoreAudio / DisplayServices-backed controllers for the actual adjustment.
@MainActor
@Observable
final class MediaKeyInterceptor {
    /// True while the key tap is installed (macOS bezel suppressed).
    private(set) var isActive = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let audio: AudioController
    @ObservationIgnored private let brightness: BrightnessController
    @ObservationIgnored private let onVolume: () -> Void
    @ObservationIgnored private let onBrightness: () -> Void

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    // NX_SYSDEFINED media-key codes.
    private static let systemDefinedType: UInt32 = 14
    private static let keySoundUp = 0
    private static let keySoundDown = 1
    private static let keyBrightnessUp = 2
    private static let keyBrightnessDown = 3
    private static let keyMute = 7
    private static let volumeStep: Float = 1.0 / 16.0
    private static let brightnessStep: Float = 1.0 / 16.0

    init(
        settings: AppSettings,
        audio: AudioController,
        brightness: BrightnessController,
        onVolume: @escaping () -> Void,
        onBrightness: @escaping () -> Void
    ) {
        self.settings = settings
        self.audio = audio
        self.brightness = brightness
        self.onVolume = onVolume
        self.onBrightness = onBrightness
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    // MARK: - Lifecycle

    private func start() {
        guard tap == nil else { return }
        if !installTap() { scheduleRetry() }
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
        isActive = false
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedType)
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(info).takeUnretainedValue()
                return MainActor.assumeIsolated { interceptor.handle(type: type, event: event) }
            },
            userInfo: info
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int((nsEvent.data1 & 0xFFFF0000) >> 16)
        let keyFlags = nsEvent.data1 & 0xFFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        // Shift+Option gives quarter steps, matching macOS exactly.
        let fine = event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)

        switch keyCode {
        case Self.keySoundUp, Self.keySoundDown, Self.keyMute:
            // Leave the keys to macOS when there is nothing we can control.
            guard audio.hasOutputDevice else { return Unmanaged.passUnretained(event) }
            // Consume both down and up so macOS never shows its bezel; act on
            // down (repeats arrive as further key-downs, so holding works).
            if isKeyDown { handleVolumeKey(keyCode, fine: fine) }
            return nil

        case Self.keyBrightnessUp, Self.keyBrightnessDown:
            // Only take over when we can actually set brightness on this display.
            guard brightness.isAvailable else { return Unmanaged.passUnretained(event) }
            if isKeyDown { handleBrightnessKey(keyCode, fine: fine) }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleVolumeKey(_ keyCode: Int, fine: Bool) {
        let step = fine ? Self.volumeStep / 4 : Self.volumeStep
        switch keyCode {
        case Self.keyMute:
            _ = audio.toggleMute()
        case Self.keySoundUp:
            audio.setVolume(min(audio.volume + step, 1))
        default:
            audio.setVolume(max(audio.volume - step, 0))
        }
        onVolume()
    }

    private func handleBrightnessKey(_ keyCode: Int, fine: Bool) {
        let step = fine ? Self.brightnessStep / 4 : Self.brightnessStep
        let delta: Float = keyCode == Self.keyBrightnessUp ? step : -step
        brightness.setBrightness(min(max(brightness.brightness + delta, 0), 1))
        onBrightness()
    }
}
