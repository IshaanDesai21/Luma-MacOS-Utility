import CoreGraphics
import Foundation
import Observation

/// Reads and writes the main display's brightness through the private
/// DisplayServices framework, loaded at runtime so the app links cleanly.
@MainActor
@Observable
final class BrightnessController {
    private(set) var brightness: Float = 0.5
    private(set) var isAvailable = false

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    @ObservationIgnored private var handle: UnsafeMutableRawPointer?
    @ObservationIgnored private var getFn: GetBrightness?
    @ObservationIgnored private var setFn: SetBrightness?

    init() {
        load()
        refresh()
    }

    private func load() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        self.handle = handle

        if let getSym = dlsym(handle, "DisplayServicesGetBrightness") {
            getFn = unsafeBitCast(getSym, to: GetBrightness.self)
        }
        if let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
            setFn = unsafeBitCast(setSym, to: SetBrightness.self)
        }
        isAvailable = getFn != nil && setFn != nil
    }

    func refresh() {
        guard let getFn else { return }
        var value: Float = 0
        if getFn(CGMainDisplayID(), &value) == 0 {
            brightness = value
        }
    }

    func setBrightness(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        brightness = clamped
        _ = setFn?(CGMainDisplayID(), clamped)
    }
}
