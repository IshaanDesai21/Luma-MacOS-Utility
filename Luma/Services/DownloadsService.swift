import AppKit
import Observation

/// Watches the Downloads folder and surfaces recent and in-progress downloads.
@MainActor
@Observable
final class DownloadsService {
    struct Item: Identifiable, Hashable {
        var path: String
        var name: String
        var sizeBytes: Int64
        var inProgress: Bool
        var id: String { path }
        var url: URL { URL(fileURLWithPath: path) }
    }

    private(set) var items: [Item] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let directory = FileManager.default
        .homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
    private let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]

    /// Files modified at/before this are hidden from the list (Clear button).
    /// This only clears the display; the files themselves stay in Downloads.
    @ObservationIgnored private var clearedBefore: Date?

    var activeCount: Int { items.filter(\.inProgress).count }

    /// Hides the current list; new downloads still appear as they arrive.
    func clearList() {
        clearedBefore = Date()
        items = []
    }

    func start(interval: Duration = .seconds(2)) {
        guard task == nil else { return }
        refresh()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self?.refresh()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }

        var dated: [(Item, Date)] = []
        for url in entries {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let ext = url.pathExtension.lowercased()
            let inProgress = partialExtensions.contains(ext)
            if values?.isDirectory == true && !inProgress { continue }
            let item = Item(
                path: url.path(percentEncoded: false),
                name: url.deletingPathExtension().lastPathComponent,
                sizeBytes: Int64(values?.fileSize ?? 0),
                inProgress: inProgress
            )
            let modified = values?.contentModificationDate ?? .distantPast
            // Respect a Clear: only show items newer than the cleared cutoff.
            if let clearedBefore, modified <= clearedBefore { continue }
            dated.append((item, modified))
        }
        dated.sort { $0.1 > $1.1 }
        items = Array(dated.prefix(8)).map(\.0)
    }

    func icon(for item: Item) -> NSImage { NSWorkspace.shared.icon(forFile: item.path) }
    func open(_ item: Item) { NSWorkspace.shared.open(item.url) }
    func reveal(_ item: Item) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    func formattedSize(_ item: Item) -> String {
        ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file)
    }
}
