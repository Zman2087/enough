import XCTest
@testable import FilterEngine

final class DayBoundaryTests: XCTestCase {
    private let calendar = FixturePaths.newYorkCalendar()

    func testBeforeResetBelongsToPreviousDay() {
        let boundary = DayBoundary(hour: 4, minute: 0, calendar: calendar)
        let early = FixturePaths.date(2026, 11, 3, 3, 59, calendar: calendar)
        XCTAssertEqual(boundary.key(for: early).rawValue, "2026-11-02")
    }

    func testResetInstantStartsTheNewDay() {
        let boundary = DayBoundary(hour: 4, minute: 0, calendar: calendar)
        let atReset = FixturePaths.date(2026, 11, 3, 4, 0, calendar: calendar)
        let evening = FixturePaths.date(2026, 11, 3, 23, 30, calendar: calendar)
        let nextMorning = FixturePaths.date(2026, 11, 4, 3, 59, calendar: calendar)
        XCTAssertEqual(boundary.key(for: atReset).rawValue, "2026-11-03")
        XCTAssertEqual(boundary.key(for: evening).rawValue, "2026-11-03")
        XCTAssertEqual(boundary.key(for: nextMorning).rawValue, "2026-11-03")
    }

    func testMidnightResetMatchesTheCalendarDay() {
        let boundary = DayBoundary(hour: 0, minute: 0, calendar: calendar)
        let late = FixturePaths.date(2026, 11, 3, 23, 59, calendar: calendar)
        let midnight = FixturePaths.date(2026, 11, 4, 0, 0, calendar: calendar)
        XCTAssertEqual(boundary.key(for: late).rawValue, "2026-11-03")
        XCTAssertEqual(boundary.key(for: midnight).rawValue, "2026-11-04")
    }

    func testNextResetBeforeAndAfterTheBoundary() {
        let boundary = DayBoundary(hour: 4, minute: 0, calendar: calendar)
        let before = FixturePaths.date(2026, 11, 3, 3, 0, calendar: calendar)
        let after = FixturePaths.date(2026, 11, 3, 17, 0, calendar: calendar)
        XCTAssertEqual(boundary.nextReset(after: before), FixturePaths.date(2026, 11, 3, 4, 0, calendar: calendar))
        XCTAssertEqual(boundary.nextReset(after: after), FixturePaths.date(2026, 11, 4, 4, 0, calendar: calendar))
        XCTAssertEqual(boundary.resetClockText(at: after), "4:00 AM")
    }

    func testHalfHourReset() {
        let boundary = DayBoundary(hour: 4, minute: 30, calendar: calendar)
        let before = FixturePaths.date(2026, 11, 3, 4, 29, calendar: calendar)
        let at = FixturePaths.date(2026, 11, 3, 4, 30, calendar: calendar)
        XCTAssertEqual(boundary.key(for: before).rawValue, "2026-11-02")
        XCTAssertEqual(boundary.key(for: at).rawValue, "2026-11-03")
    }

    func testSpringForwardGapDoesNotCrash() {
        // 2:30 AM does not exist in New York on 8 March 2026.
        let boundary = DayBoundary(hour: 2, minute: 30, calendar: calendar)
        let beforeGap = FixturePaths.date(2026, 3, 8, 1, 30, calendar: calendar)
        let afterGap = FixturePaths.date(2026, 3, 8, 3, 30, calendar: calendar)
        XCTAssertEqual(boundary.key(for: beforeGap).rawValue, "2026-03-07")
        XCTAssertEqual(boundary.key(for: afterGap).rawValue, "2026-03-08")
        let next = boundary.nextReset(after: beforeGap)
        XCTAssertGreaterThan(next, beforeGap)
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: next)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 3)
        XCTAssertEqual(parts.day, 8)
        XCTAssertGreaterThanOrEqual(parts.hour ?? 0, 3)
    }

    func testFallBackHourStillUsesThePreviousDayBeforeReset() {
        let boundary = DayBoundary(hour: 4, minute: 0, calendar: calendar)
        let overlap = FixturePaths.date(2026, 11, 1, 1, 30, calendar: calendar)
        XCTAssertEqual(boundary.key(for: overlap).rawValue, "2026-10-31")
    }
}
