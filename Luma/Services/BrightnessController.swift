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
        lastObserved = clamped
        _ = setFn?(CGMainDisplayID(), clamped)
    }

    // MARK: - Change observation

    @ObservationIgnored private var observeTask: Task<Void, Never>?
    @ObservationIgnored private var lastObserved: Float = -1
    @ObservationIgnored private var changeHandler: (@MainActor () -> Void)?

    /// Reports brightness changes from anywhere (keys, Control Center, auto
    /// brightness) by polling the display, so the island can pop its readout
    /// even when key interception isn't available.
    func startObservingSystemChanges(_ handler: @escaping @MainActor () -> Void) {
        changeHandler = handler
        guard observeTask == nil, isAvailable else { return }
        lastObserved = brightness
        observeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                self?.checkForChange()
            }
        }
    }

    private func checkForChange() {
        refresh()
        if lastObserved < 0 { lastObserved = brightness }
        if abs(brightness - lastObserved) > 0.004 {
            lastObserved = brightness
            changeHandler?()
        }
    }
}
