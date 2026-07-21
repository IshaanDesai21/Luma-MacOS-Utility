import Foundation
import Observation

/// Lists the top processes by resident memory via `ps`, for the Memory module's
/// detailed breakdown. Read-only and unprivileged.
@MainActor
@Observable
final class ProcessMemoryReader {
    struct Process: Identifiable, Hashable {
        let pid: Int
        let name: String
        let residentBytes: Int64
        var id: Int { pid }
        var megabytes: Double { Double(residentBytes) / 1_048_576 }
    }

    private(set) var processes: [Process] = []
    private(set) var isLoading = false

    /// Loads the top `limit` processes by memory, coalescing similar names.
    func reload(limit: Int = 8) async {
        isLoading = true
        defer { isLoading = false }
        let output = await Self.runPS()
        processes = Self.parse(output, limit: limit)
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

    private static func parse(_ output: String, limit: Int) -> [Process] {
        var merged: [String: (bytes: Int64, pid: Int)] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = trimmed.firstIndex(of: " ") else { continue }
            let rssPart = trimmed[..<firstSpace]
            guard let rssKB = Int64(rssPart) else { continue }
            let rest = trimmed[trimmed.index(after: firstSpace)...].trimmingCharacters(in: .whitespaces)
            guard let secondSpace = rest.firstIndex(of: " ") else { continue }
            let pid = Int(rest[..<secondSpace]) ?? 0
            let commandPath = String(rest[rest.index(after: secondSpace)...])
            let name = friendlyName(commandPath)

            let bytes = rssKB * 1024
            if let existing = merged[name] {
                merged[name] = (existing.bytes + bytes, existing.pid)
            } else {
                merged[name] = (bytes, pid)
            }
        }

        return merged
            .map { Process(pid: $0.value.pid, name: $0.key, residentBytes: $0.value.bytes) }
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
