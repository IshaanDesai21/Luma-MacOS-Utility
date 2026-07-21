import AppKit
import Foundation
import Observation

/// Lists the top processes by resident memory via `ps`, for the Memory module's
/// detailed breakdown. Can also terminate a process at the user's request.
@MainActor
@Observable
final class ProcessMemoryReader {
    struct Entry: Identifiable, Hashable {
        let pid: Int
        let name: String
        let residentBytes: Int64
        var id: Int { pid }
        var megabytes: Double { Double(residentBytes) / 1_048_576 }
    }

    private(set) var processes: [Entry] = []
    private(set) var isLoading = false

    @ObservationIgnored private var iconCache: [String: NSImage] = [:]

    /// Loads the top `limit` processes by memory, coalescing similar names.
    func reload(limit: Int = 8) async {
        isLoading = true
        defer { isLoading = false }
        let output = await Self.runPS()
        processes = Self.parse(output, limit: limit)
    }

    /// The app's icon when the pid belongs to a regular app; nil otherwise.
    func icon(for entry: Entry) -> NSImage? {
        if let cached = iconCache[entry.name] { return cached }
        guard let app = NSRunningApplication(processIdentifier: pid_t(entry.pid)),
              let icon = app.icon else { return nil }
        iconCache[entry.name] = icon
        return icon
    }

    /// Asks the process to quit (SIGTERM), then refreshes the list.
    func terminate(_ entry: Entry) {
        if let app = NSRunningApplication(processIdentifier: pid_t(entry.pid)) {
            app.terminate()
        } else {
            kill(pid_t(entry.pid), SIGTERM)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            await self?.reload()
        }
    }

    private static func runPS() async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Foundation.Process()
                process.executableURL = URL(fileURLWithPath: "/bin/ps")
                // rss (KB), pid, and full command, sorted by memory descending.
                process.arguments = ["-axo", "rss=,pid=,comm=", "-r"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }

    private static func parse(_ output: String, limit: Int) -> [Entry] {
        // Keep the LARGEST pid's usage per app name group, summing helpers, and
        // remember the pid of the biggest contributor so kill hits the main app.
        var merged: [String: (bytes: Int64, pid: Int, biggest: Int64)] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = trimmed.firstIndex(of: " ") else { continue }
            guard let rssKB = Int64(trimmed[..<firstSpace]) else { continue }
            let rest = trimmed[trimmed.index(after: firstSpace)...].trimmingCharacters(in: .whitespaces)
            guard let secondSpace = rest.firstIndex(of: " ") else { continue }
            let pid = Int(rest[..<secondSpace]) ?? 0
            let commandPath = String(rest[rest.index(after: secondSpace)...])
            let name = friendlyName(commandPath)

            let bytes = rssKB * 1024
            if let existing = merged[name] {
                let biggestPID = bytes > existing.biggest ? pid : existing.pid
                merged[name] = (existing.bytes + bytes, biggestPID, max(existing.biggest, bytes))
            } else {
                merged[name] = (bytes, pid, bytes)
            }
        }

        return merged
            .map { Entry(pid: $0.value.pid, name: $0.key, residentBytes: $0.value.bytes) }
            .sorted { $0.residentBytes > $1.residentBytes }
            .prefix(limit)
            .map { $0 }
    }

    /// Turns a command path like `/Applications/Safari.app/Contents/MacOS/Safari`
    /// into a readable app name.
    private static func friendlyName(_ path: String) -> String {
        if let range = path.range(of: ".app/") {
            let appName = path[..<range.lowerBound]
            if let slash = appName.lastIndex(of: "/") {
                return String(appName[appName.index(after: slash)...])
            }
            return String(appName)
        }
        if let slash = path.lastIndex(of: "/") {
            return String(path[path.index(after: slash)...])
        }
        return path
    }
}
