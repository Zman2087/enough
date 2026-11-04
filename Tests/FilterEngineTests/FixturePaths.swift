import Foundation

enum FixturePaths {
    static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    static var routes: URL {
        testsDirectory.appendingPathComponent("Fixtures/routes.json")
    }

    static var repoRoot: URL {
        testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var selectors: URL {
        repoRoot.appendingPathComponent("Sources/FilterEngine/Resources/selectors.json")
    }

    static var hideCSS: URL {
        repoRoot.appendingPathComponent("Sources/FilterEngine/Resources/hide.css")
    }

    static func newYorkCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts)!
    }
}

struct RouteFixture: Decodable {
    var path: String
    var surface: String
    var blockedAtCap: Bool
}
