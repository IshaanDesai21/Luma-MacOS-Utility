import AppKit
import EventKit
import Observation

/// Reads today's calendar events for the island's calendar panel. Uses EventKit,
/// so it covers Apple Calendar and any Google/Exchange account the user has
/// added to the system Calendar app.
@MainActor
@Observable
final class CalendarService {
    struct Event: Identifiable, Hashable {
        let id: String
        let title: String
        let start: Date
        let isAllDay: Bool
        let calendarColor: NSColor
    }

    enum Access { case unknown, granted, denied }

    private(set) var todaysEvents: [Event] = []
    private(set) var access: Access = .unknown

    /// The day the strip is centered on and whose events are listed. Starts at
    /// today; scrolling the strip moves it.
    private(set) var focusedDate = Calendar.current.startOfDay(for: Date())

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// Seven days centered on the focused day.
    var weekDays: [Date] {
        let calendar = Calendar.current
        return (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: focusedDate) }
    }

    var isFocusedToday: Bool {
        Calendar.current.isDateInToday(focusedDate)
    }

    /// Moves the focused day (from scrolling the strip) and reloads its events.
    func shift(days: Int) {
        guard days != 0 else { return }
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: days, to: focusedDate) else { return }
        focusedDate = next
        reload()
    }

    func focusToday() {
        focusedDate = Calendar.current.startOfDay(for: Date())
        reload()
    }

    /// Opens System Settings > Internet Accounts so the user can add a Google
    /// (or other) account; EventKit then shows those events with no OAuth here.
    func openInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        requestAccess()
        // React to external calendar edits.
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // Light periodic refresh so "today" and event times stay current.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.reload()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func requestAccess() {
        // Only prompt when the user hasn't decided yet; otherwise reflect the
        // existing decision (reading events needs full access).
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            reload()
        case .notDetermined:
            // The completion is delivered on an arbitrary queue, so hop to the
            // main actor explicitly (assumeIsolated would trap off-main).
            store.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.access = granted ? .granted : .denied
                    if granted { self.reload() }
                }
            }
        default:
            access = .denied
        }
    }

    func reload() {
        guard access == .granted else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: focusedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let focusedIsToday = calendar.isDateInToday(focusedDate)

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            // On today, hide events that already finished; on other days show all.
            .filter { focusedIsToday && !$0.isAllDay ? $0.endDate > Date() : true }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .prefix(12)
            .map {
                Event(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "Untitled",
                    start: $0.startDate ?? start,
                    isAllDay: $0.isAllDay,
                    calendarColor: $0.calendar?.color ?? .systemBlue
                )
            }
        todaysEvents = Array(events)
    }

    /// Opens the system Calendar app (which shows Google/iCloud events alike).
    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let web = URL(string: "https://calendar.google.com") {
            NSWorkspace.shared.open(web)
        }
    }

    func requestAccessAgain() {
        if access == .denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        } else {
            requestAccess()
        }
    }
}
