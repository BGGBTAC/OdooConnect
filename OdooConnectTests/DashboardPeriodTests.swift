import Testing
import Foundation
@testable import OdooConnect

@Suite struct DashboardPeriodTests {
    // Pin `now` and a UTC calendar for deterministic boundaries.
    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private static let now = utc.date(
        from: DateComponents(year: 2026, month: 6, day: 15, hour: 10, minute: 30)
    )!

    @Test func todayStartsAtMidnight() {
        let r = DashboardPeriod.today.range(now: Self.now, calendar: Self.utc)
        #expect(r.end == Self.now)
        #expect(r.start == Self.utc.startOfDay(for: Self.now))
    }

    @Test func mtdStartsFirstOfMonth() {
        let r = DashboardPeriod.mtd.range(now: Self.now, calendar: Self.utc)
        #expect(r.start == Self.utc.date(from: DateComponents(year: 2026, month: 6, day: 1))!)
    }

    @Test func ytdStartsFirstOfYear() {
        let r = DashboardPeriod.ytd.range(now: Self.now, calendar: Self.utc)
        #expect(r.start == Self.utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!)
    }

    @Test func last7SpansSixDaysBack() {
        let r = DashboardPeriod.last7.range(now: Self.now, calendar: Self.utc)
        let expected = Self.utc.date(
            byAdding: .day, value: -6, to: Self.utc.startOfDay(for: Self.now)
        )!
        #expect(r.start == expected)
    }

    @Test func previousRangeSameLengthEndsAtCurrentStart() {
        let cur = DashboardPeriod.ytd.range(now: Self.now, calendar: Self.utc)
        let prev = DashboardPeriod.ytd.previousRange(now: Self.now, calendar: Self.utc)
        #expect(prev.end == cur.start)
        let curLen = cur.end.timeIntervalSince(cur.start)
        let prevLen = prev.end.timeIntervalSince(prev.start)
        #expect(abs(curLen - prevLen) < 0.001)
    }
}
