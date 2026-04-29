import Foundation

enum DashboardPeriod: String, CaseIterable, Identifiable, Sendable {
    case today, last7, mtd, ytd

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Heute"
        case .last7: return "7 Tage"
        case .mtd:   return "Monat"
        case .ytd:   return "Jahr"
        }
    }

    /// Series bucket size. Drives both the Odoo `read_group` grouping
    /// and client-side chart `unit`.
    var seriesInterval: SeriesInterval {
        switch self {
        case .today: return .hour
        case .last7: return .day
        case .mtd:   return .day
        case .ytd:   return .week
        }
    }

    enum SeriesInterval: String, Sendable {
        case hour, day, week

        /// Odoo `read_group` field suffix.
        var odooSuffix: String { rawValue }
    }

    struct Range: Sendable {
        let start: Date
        let end: Date
    }

    func range(now: Date = .now, calendar: Calendar = .current) -> Range {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return Range(start: start, end: now)
        case .last7:
            let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            return Range(start: start, end: now)
        case .mtd:
            // First day of the current month at 00:00 — "Month to Date".
            let comps = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: comps) ?? calendar.startOfDay(for: now)
            return Range(start: start, end: now)
        case .ytd:
            let comps = calendar.dateComponents([.year], from: now)
            let start = calendar.date(from: comps) ?? now
            return Range(start: start, end: now)
        }
    }

    /// Equivalent previous-period range, used for delta comparison.
    func previousRange(now: Date = .now, calendar: Calendar = .current) -> Range {
        let current = range(now: now, calendar: calendar)
        let length = current.end.timeIntervalSince(current.start)
        let end = current.start
        let start = end.addingTimeInterval(-length)
        return Range(start: start, end: end)
    }
}
