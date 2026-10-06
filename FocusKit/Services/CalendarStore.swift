import EventKit
import Observation
import SwiftUI

@MainActor
@Observable
final class CalendarStore {
    enum Access: Equatable {
        case unknown
        case granted
        case denied
    }

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let location: String?
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: Color
    }

    private(set) var access = Access.unknown
    private(set) var events: [Event] = []
    var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    var selected = Calendar.current.startOfDay(for: .now)

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        access = Self.currentAccess
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        if access == .granted { reload() }
    }

    private static var currentAccess: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }

    func refresh() {
        let current = Self.currentAccess
        if current != access, current == .granted {
            store.reset()
        }
        access = current
        reload()
    }

    func prepare() async {
        refresh()
        if access == .unknown {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
        }
        reload()
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func openCalendar() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    func showMonth(offset: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: offset, to: month) else { return }
        month = next
        reload()
    }

    func select(_ day: Date) {
        selected = Calendar.current.startOfDay(for: day)
        let calendar = Calendar.current
        if !calendar.isDate(day, equalTo: month, toGranularity: .month), let start = calendar.dateInterval(of: .month, for: day)?.start {
            month = start
            reload()
        }
    }

    var days: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -leading, to: interval.start) else { return [] }
        let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let count = Int((Double(leading + length) / 7).rounded(.up)) * 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    func events(on day: Date) -> [Event] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return events.filter { $0.start < interval.end && $0.end > interval.start }
    }

    func hasEvents(on day: Date) -> Bool {
        !events(on: day).isEmpty
    }

    var upcoming: [Event] {
        let now = Date.now
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        return events.filter { $0.end > now && $0.start < end && !$0.isAllDay }
    }

    private func reload() {
        access = Self.currentAccess
        guard access == .granted, let first = days.first, let last = days.last,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else {
            events = []
            return
        }
        let today = Calendar.current.startOfDay(for: .now)
        let start = min(first, today)
        let finish = max(end, Calendar.current.date(byAdding: .day, value: 2, to: today) ?? end)
        let predicate = store.predicateForEvents(withStart: start, end: finish, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                Event(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    location: event.location?.split(separator: "\n").first.map(String.init),
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: Color(cgColor: event.calendar?.cgColor ?? NSColor.systemBlue.cgColor)
                )
            }
    }
}
