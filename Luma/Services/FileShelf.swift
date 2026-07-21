import AppKit
import Observation

/// Holds files the user drops in for later use. Persists paths across launches.
@MainActor
@Observable
final class FileShelf {
    struct Item: Identifiable, Codable, Hashable {
        var id: UUID
        var path: String
        var name: String
        var url: URL { URL(fileURLWithPath: path) }
    }

    private(set) var items: [Item] = []
    private let storageKey = "fileShelf.items"

    init() {
        load()
    }

    func add(urls: [URL]) {
        for url in urls {
            let path = url.path(percentEncoded: false)
            guard !items.contains(where: { $0.path == path }) else { continue }
            items.append(Item(id: UUID(), path: path, name: url.lastPathComponent))
        }
        persist()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func icon(for item: Item) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.path)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
