import CoreAudio
import Foundation

/// Thin, value-typed wrapper around a CoreAudio device for reading and writing
/// volume and mute on a given scope (input or output).
struct AudioDevice {
    let id: AudioDeviceID

    static func defaultDevice(input: Bool) -> AudioDevice? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return AudioDevice(id: deviceID)
    }

    // MARK: - Mute

    func hasMute(scope: AudioObjectPropertyScope) -> Bool {
        var addr = muteAddress(scope)
        return AudioObjectHasProperty(id, &addr)
    }

    func isMuteSettable(scope: AudioObjectPropertyScope) -> Bool {
        var addr = muteAddress(scope)
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(id, &addr, &settable)
        return status == noErr && settable.boolValue
    }

    func getMute(scope: AudioObjectPropertyScope) -> Bool {
        var addr = muteAddress(scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    @discardableResult
    func setMute(_ muted: Bool, scope: AudioObjectPropertyScope) -> Bool {
        var addr = muteAddress(scope)
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, size, &value) == noErr
    }

    // MARK: - Volume

    func getVolume(scope: AudioObjectPropertyScope) -> Float? {
        var addr = volumeAddress(scope)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    @discardableResult
    func setVolume(_ volume: Float, scope: AudioObjectPropertyScope) -> Bool {
        var addr = volumeAddress(scope)
        var value = Float32(min(max(volume, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, size, &value) == noErr
    }

    // MARK: - Listener

    func addMuteListener(scope: AudioObjectPropertyScope, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) {
        var addr = muteAddress(scope)
        AudioObjectAddPropertyListenerBlock(id, &addr, queue, block)
    }

    func removeMuteListener(scope: AudioObjectPropertyScope, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) {
        var addr = muteAddress(scope)
        AudioObjectRemovePropertyListenerBlock(id, &addr, queue, block)
    }

    func addVolumeListener(scope: AudioObjectPropertyScope, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) {
        var addr = volumeAddress(scope)
        AudioObjectAddPropertyListenerBlock(id, &addr, queue, block)
    }

    func removeVolumeListener(scope: AudioObjectPropertyScope, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) {
        var addr = volumeAddress(scope)
        AudioObjectRemovePropertyListenerBlock(id, &addr, queue, block)
    }

    /// Observes the system-wide default output/input device switching (e.g.
    /// connecting AirPods), so callers can re-register per-device listeners.
    static func addDefaultDeviceListener(input: Bool, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) {
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
    }

    // MARK: - Addresses

    private func muteAddress(_ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func volumeAddress(_ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
