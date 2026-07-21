import Carbon
import AppKit
import Observation

/// Tracks and switches the active keyboard input source (e.g. English / Spanish).
@MainActor
@Observable
final class InputSourceController {
    private(set) var name = ""
    private(set) var abbreviation = ""

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        name = Self.string(source, kTISPropertyLocalizedName) ?? ""
        if let code = Self.language(source) {
            abbreviation = code.uppercased()
        } else {
            abbreviation = String(name.prefix(2)).uppercased()
        }
    }

    /// Switches to the next selectable keyboard input source.
    func cycle() {
        let sources = Self.selectableSources()
        guard sources.count > 1,
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        let currentID = Self.string(current, kTISPropertyInputSourceID)
        let index = sources.firstIndex { Self.string($0, kTISPropertyInputSourceID) == currentID } ?? 0
        let next = sources[(index + 1) % sources.count]
        TISSelectInputSource(next)
        refresh()
    }

    // MARK: - Helpers

    private static func selectableSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.filter { source in
            guard let category = string(source, kTISPropertyInputSourceCategory) else { return false }
            let selectable = bool(source, kTISPropertyInputSourceIsSelectCapable)
            return category == (kTISCategoryKeyboardInputSource as String) && selectable
        }
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue() == kCFBooleanTrue
    }

    private static func language(_ source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return nil }
        let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        return languages?.first
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}
