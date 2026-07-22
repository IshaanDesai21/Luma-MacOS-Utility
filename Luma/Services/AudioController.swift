import CoreAudio
import Foundation
import Observation

/// Reads and writes the default output device's volume and mute, and reports
/// changes made anywhere in the system (keys, menu bar slider, AirPods, other
/// apps) so the island can pop its readout.
@MainActor
@Observable
final class AudioController {
    private(set) var volume: Float = 0.5
    private(set) var isMuted = false

    private let scope = kAudioObjectPropertyScopeOutput

    private var device: AudioDevice? { AudioDevice.defaultDevice(input: false) }

    /// Whether there is an output device we can actually control. When false,
    /// callers should leave the hardware keys to macOS.
    var hasOutputDevice: Bool { device != nil }

    @ObservationIgnored private var externalChangeHandler: (@MainActor () -> Void)?
    @ObservationIgnored private var listenedDevice: AudioDevice?
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?

    init() {
        refresh()
    }

    /// Starts reporting volume/mute changes from anywhere in the system. The
    /// handler runs on the main actor after `volume`/`isMuted` are refreshed.
    func startObservingSystemChanges(_ handler: @escaping @MainActor () -> Void) {
        externalChangeHandler = handler
        installDeviceListeners()
        // Re-register when the default output device changes (AirPods etc.).
        AudioDevice.addDefaultDeviceListener(input: false, queue: .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.installDeviceListeners()
                self?.notifyExternalChange()
            }
        }
    }

    private func installDeviceListeners() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.notifyExternalChange() }
        }
        if let old = listenedDevice, let oldListener = deviceListener {
            old.removeVolumeListener(scope: scope, queue: .main, block: oldListener)
            old.removeMuteListener(scope: scope, queue: .main, block: oldListener)
        }
        guard let device else {
            listenedDevice = nil
            deviceListener = nil
            return
        }
        device.addVolumeListener(scope: scope, queue: .main, block: listener)
        if device.hasMute(scope: scope) {
            device.addMuteListener(scope: scope, queue: .main, block: listener)
        }
        listenedDevice = device
        deviceListener = listener
    }

    private func notifyExternalChange() {
        refresh()
        externalChangeHandler?()
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
