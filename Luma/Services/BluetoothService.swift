import Foundation
import IOBluetooth
import Observation

/// Lists paired Bluetooth devices and connects/disconnects them, for the
/// island's Bluetooth tab. Uses the public IOBluetooth (classic) API, which
/// covers headphones, AirPods, mice, keyboards, and game controllers.
@MainActor
@Observable
final class BluetoothService {
    struct Device: Identifiable, Hashable {
        let id: String          // address string
        let name: String
        let connected: Bool
        let majorClass: UInt32  // for choosing an icon
    }

    private(set) var devices: [Device] = []
    private(set) var isPowered = true

    /// Device ids with a connect/disconnect currently in progress (shows a
    /// looping spinner in the row).
    private(set) var inFlight: Set<String> = []

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    func isBusy(_ device: Device) -> Bool { inFlight.contains(device.id) }

    func start() {
        guard pollTask == nil else { return }
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        if let host = IOBluetoothHostController.default() {
            isPowered = host.powerState == kBluetoothHCIPowerStateON
        }
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        devices = paired.map {
            Device(
                id: $0.addressString ?? UUID().uuidString,
                name: $0.name ?? ($0.addressString ?? "Unknown"),
                connected: $0.isConnected(),
                majorClass: $0.deviceClassMajor
            )
        }
        // Connected first, then alphabetical.
        .sorted { ($0.connected ? 0 : 1, $0.name.lowercased()) < ($1.connected ? 0 : 1, $1.name.lowercased()) }
    }

    /// Connects a disconnected device or disconnects a connected one, showing a
    /// spinner on the row until it settles.
    func toggle(_ device: Device) {
        guard !inFlight.contains(device.id) else { return }
        guard let match = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?
            .first(where: { $0.addressString == device.id }) else { return }

        inFlight.insert(device.id)
        Task { @MainActor in
            if match.isConnected() {
                _ = match.closeConnection()
            } else {
                // openConnection() blocks briefly; run it off the main actor.
                await Task.detached { _ = match.openConnection() }.value
            }
            // Reflect the new state after the stack settles.
            try? await Task.sleep(for: .milliseconds(400))
            self.refresh()
            self.inFlight.remove(device.id)
        }
    }

    /// An SF Symbol for the device's major class.
    static func symbol(forMajorClass majorClass: UInt32) -> String {
        switch majorClass {
        case UInt32(kBluetoothDeviceClassMajorAudio): return "headphones"
        case UInt32(kBluetoothDeviceClassMajorPeripheral): return "keyboard"
        case UInt32(kBluetoothDeviceClassMajorPhone): return "iphone"
        case UInt32(kBluetoothDeviceClassMajorComputer): return "laptopcomputer"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
