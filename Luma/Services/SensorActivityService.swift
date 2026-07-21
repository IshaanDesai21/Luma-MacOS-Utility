import CoreAudio
import CoreMediaIO
import IOKit.ps
import Observation

/// Watches whether any app is using the camera or microphone (for the
/// iOS-style activity dots in the island's resting pod) and whether the Mac is
/// charging. Polls the public "is running somewhere" device properties — no
/// permissions needed.
@MainActor
@Observable
final class SensorActivityService {
    private(set) var cameraActive = false
    private(set) var micActive = false
    private(set) var isCharging = false

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        cameraActive = false
        micActive = false
        isCharging = false
    }

    private func poll() {
        let camera = Self.isAnyCameraRunning()
        let mic = Self.isMicrophoneRunning()
        let charging = Self.isChargingNow()
        if camera != cameraActive { cameraActive = camera }
        if mic != micActive { micActive = mic }
        if charging != isCharging { isCharging = charging }
    }

    // MARK: - Camera (CoreMediaIO)

    private static func isAnyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize) == 0,
              dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, dataSize, &dataUsed, &devices) == 0 else {
            return false
        }

        var runningAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        for device in devices {
            var running: UInt32 = 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            var used: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, size, &used, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    // MARK: - Charging (IOKit)

    private static func isChargingNow() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let charging = info[kIOPSIsChargingKey as String] as? Bool,
               charging {
                return true
            }
        }
        return false
    }

    // MARK: - Microphone (CoreAudio)

    private static func isMicrophoneRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &runningSize, &running) == noErr else {
            return false
        }
        return running != 0
    }
}
