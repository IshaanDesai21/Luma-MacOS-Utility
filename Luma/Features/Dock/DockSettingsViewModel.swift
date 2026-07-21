import Foundation
import Observation

/// Mirrors the live `com.apple.dock` settings and writes changes back with a
/// short debounce so dragging a slider doesn't restart the Dock repeatedly.
@MainActor
@Observable
final class DockSettingsViewModel {
    var preferences: DockPreferences {
        didSet { if !suppressApply { scheduleApply() } }
    }

    @ObservationIgnored private let service = DockPreferencesService()
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var suppressApply = false

    init(service: DockPreferencesService = DockPreferencesService()) {
        preferences = service.load()
    }

    func reload() {
        suppressApply = true
        preferences = service.load()
        suppressApply = false
    }

    private func scheduleApply() {
        applyTask?.cancel()
        let snapshot = preferences
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            try? await self.service.apply(snapshot)
        }
    }
}
