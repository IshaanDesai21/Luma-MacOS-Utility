import Foundation
import Darwin
import IOKit.ps
import Observation

/// Periodically samples system metrics (CPU, memory, battery, network, time)
/// and publishes them for modules to display.
@MainActor
@Observable
final class SystemMonitor {
    private(set) var date = Date(timeIntervalSince1970: 0)
    private(set) var cpuUsage: Double = 0            // 0...1
    private(set) var memoryUsedFraction: Double = 0  // 0...1
    private(set) var memoryUsedGB: Double = 0
    private(set) var memoryTotalGB: Double = 0
    private(set) var swapUsedGB: Double = 0
    private(set) var batteryLevel: Double = 0        // 0...1
    private(set) var batteryCharging = false
    private(set) var hasBattery = false
    private(set) var networkDownKBps: Double = 0
    private(set) var networkUpKBps: Double = 0

    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var previousCPUTicks: (used: Double, total: Double)?
    @ObservationIgnored private var previousNet: (input: UInt64, output: UInt64)?
    @ObservationIgnored private var previousSampleDate: Date?

    func start(interval: Duration = .seconds(1)) {
        guard timerTask == nil else { return }
        sample()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self?.sample()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Sampling

    private func sample() {
        date = nowDate()
        sampleCPU()
        sampleMemory()
        sampleBattery()
        sampleNetwork()
    }

    /// `Date()` is fine here (not in a resumable workflow); isolate it in one place.
    private func nowDate() -> Date { Date() }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle

        if let previous = previousCPUTicks {
            let deltaUsed = used - previous.used
            let deltaTotal = total - previous.total
            if deltaTotal > 0 { cpuUsage = min(max(deltaUsed / deltaTotal, 0), 1) }
        }
        previousCPUTicks = (used, total)
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return }

        memoryUsedGB = used / 1_073_741_824
        memoryTotalGB = total / 1_073_741_824
        memoryUsedFraction = min(max(used / total, 0), 1)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsedGB = Double(swap.xsu_used) / 1_073_741_824
        }
    }

    private func sampleBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { hasBattery = false; return }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            hasBattery = true
            batteryLevel = Swift.min(Swift.max(Double(current) / Double(max), 0), 1)
            if let state = description[kIOPSPowerSourceStateKey] as? String {
                batteryCharging = state == kIOPSACPowerValue
            }
            return
        }
    }

    private func sampleNetwork() {
        var totals = (input: UInt64(0), output: UInt64(0))
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return }
        defer { freeifaddrs(pointer) }

        var cursor = pointer
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP,
                  let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("utun") else { continue }

            if let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                totals.input &+= UInt64(data.pointee.ifi_ibytes)
                totals.output &+= UInt64(data.pointee.ifi_obytes)
            }
        }

        let now = nowDate()
        if let previous = previousNet, let last = previousSampleDate {
            let seconds = now.timeIntervalSince(last)
            if seconds > 0 {
                let down = Double(totals.input &- previous.input) / seconds / 1024
                let up = Double(totals.output &- previous.output) / seconds / 1024
                networkDownKBps = max(down, 0)
                networkUpKBps = max(up, 0)
            }
        }
        previousNet = totals
        previousSampleDate = now
    }
}
