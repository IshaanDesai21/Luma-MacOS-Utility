import AppKit
import Observation

/// Keeps a short in-memory history of copied text (session only, for privacy).
@MainActor
@Observable
final class ClipboardService {
    struct Item: Identifiable, Hashable {
        let id: UUID
        var text: String
    }

    private(set) var items: [Item] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let pasteboard = NSPasteboard.general
    @ObservationIgnored private var lastChangeCount = 0
    private let limit = 25

    func start(interval: Duration = .milliseconds(700)) {
        guard task == nil else { return }
        lastChangeCount = pasteboard.changeCount
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self?.capture()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func copy(_ item: Item) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func clear() {
        items.removeAll()
    }

    private func capture() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        items.removeAll { $0.text == text }
        items.insert(Item(id: UUID(), text: text), at: 0)
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
    }
}
