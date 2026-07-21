import AppKit
import Observation

/// An installed application discovered on disk.
struct InstalledApp: Identifiable, Hashable {
    var name: String
    var path: String
    var bundleID: String?

    var id: String { path }

    var dockApp: DockApp {
        DockApp(name: name, path: path, bundleID: bundleID)
    }
}

/// Enumerates installed applications for the manual Dock builder.
@MainActor
@Observable
final class AppCatalog {
    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false

    private let searchPaths = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications"
    ]

    func loadIfNeeded() async {
        guard apps.isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let paths = searchPaths
        let discovered = await Task.detached(priority: .userInitiated) {
            Self.scan(paths: paths)
        }.value

        apps = discovered
    }

    /// Resolves an app's icon on demand (icons are not cached in the model).
    func icon(for app: DockApp) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.path)
    }

    // MARK: - Scanning

    private nonisolated static func scan(paths: [String]) -> [InstalledApp] {
        let fileManager = FileManager.default
        var results: [String: InstalledApp] = [:]

        for path in paths {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let fullPath = (path as NSString).appendingPathComponent(entry)
                guard results[fullPath] == nil,
                      let bundle = Bundle(path: fullPath) else { continue }

                let name = (entry as NSString).deletingPathExtension
                results[fullPath] = InstalledApp(
                    name: name,
                    path: fullPath,
                    bundleID: bundle.bundleIdentifier
                )
            }
        }

        return results.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
