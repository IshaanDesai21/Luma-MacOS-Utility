import CoreAudio
import Observation

/// Reads and writes the default output device's volume and mute.
@MainActor
@Observable
final class AudioController {
    private(set) var volume: Float = 0.5
    private(set) var isMuted = false

    private let scope = kAudioObjectPropertyScopeOutput

    private var device: AudioDevice? { AudioDevice.defaultDevice(input: false) }

    init() {
        refresh()
    }

    func refresh() {
        guard let device else { return }
        if let value = device.getVolume(scope: scope) { volume = value }
        if device.hasMute(scope: scope) { isMuted = device.getMute(scope: scope) }
    }

    func setVolume(_ value: Float) {
        volume = min(max(value, 0), 1)
        device?.setVolume(volume, scope: scope)
    }

    @discardableResult
    func toggleMute() -> Bool {
        setMuted(!isMuted)
        return isMuted
    }

    func setMuted(_ muted: Bool) {
        guard let device, device.hasMute(scope: scope) else { return }
        device.setMute(muted, scope: scope)
        isMuted = device.getMute(scope: scope)
    }
}
