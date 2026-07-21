import CoreAudio
import Observation

/// Tracks and toggles the system microphone mute state, staying in sync with
/// changes made anywhere else in the system.
///
/// Prefers the device's hardware mute property; falls back to zeroing the input
/// volume when a device doesn't expose a settable mute.
@MainActor
@Observable
final class MicrophoneController {
    private(set) var isMuted = false
    private(set) var isAvailable = false

    private let scope = kAudioObjectPropertyScopeInput

    @ObservationIgnored private var device: AudioDevice?
    @ObservationIgnored private var usesMuteProperty = false
    @ObservationIgnored private var restoreVolume: Float = 1
    @ObservationIgnored private var listener: AudioObjectPropertyListenerBlock?

    init() {
        configure()
    }

    // MARK: - Setup

    private func configure() {
        guard let device = AudioDevice.defaultDevice(input: true) else {
            isAvailable = false
            return
        }
        self.device = device
        usesMuteProperty = device.hasMute(scope: scope) && device.isMuteSettable(scope: scope)
        isAvailable = usesMuteProperty || device.getVolume(scope: scope) != nil
        refresh()
        addListener(on: device)
    }

    // MARK: - Actions

    /// Toggles mute and returns the resulting state.
    @discardableResult
    func toggle() -> Bool {
        setMuted(!isMuted)
        return isMuted
    }

    func setMuted(_ muted: Bool) {
        guard let device, isAvailable else { return }

        if usesMuteProperty {
            device.setMute(muted, scope: scope)
        } else {
            if muted {
                restoreVolume = device.getVolume(scope: scope) ?? restoreVolume
                device.setVolume(0, scope: scope)
            } else {
                device.setVolume(restoreVolume > 0 ? restoreVolume : 1, scope: scope)
            }
        }
        refresh()
    }

    func refresh() {
        guard let device else { return }
        if usesMuteProperty {
            isMuted = device.getMute(scope: scope)
        } else if let volume = device.getVolume(scope: scope) {
            isMuted = volume <= 0.0001
        }
    }

    // MARK: - System sync

    private func addListener(on device: AudioDevice) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        listener = block
        device.addMuteListener(scope: scope, queue: .main, block: block)
    }

    deinit {
        if let listener, let device {
            device.removeMuteListener(scope: scope, queue: .main, block: listener)
        }
    }
}
