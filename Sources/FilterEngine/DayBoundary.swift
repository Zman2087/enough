import Foundation

/// The calendar day Enough uses for the cap.
/// A day runs from the configured reset time until the next reset time,
/// in the calendar's time zone. It does not have to start at midnight.
public struct DayKey: Equatable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct DayBoundary: Equatable {
    public let hour: Int
    public let minute: Int
    public let calendar: Calendar

    public init(hour: Int, minute: Int, calendar: Calendar) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
        self.calendar = calendar
    }

    /// The day key for `date`. Times before the reset belong to the previous day.
    public func key(for date: Date) -> DayKey {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hourNow = parts.hour ?? 0
        let minuteNow = parts.minute ?? 0
        let beforeReset = hourNow < hour || (hourNow == hour && minuteNow < minute)
        let effective: Date
        if beforeReset, let previous = calendar.date(byAdding: .day, value: -1, to: date) {
            effective = previous
        } else {
            effective = date
        }
        let day = calendar.dateComponents([.year, .month, .day], from: effective)
        let year = day.year ?? 0
        let month = day.month ?? 0
        let dayOfMonth = day.day ?? 0
        return DayKey(rawValue: String(format: "%04d-%02d-%02d", year, month, dayOfMonth))
    }

    /// The next instant the count goes back to zero.
    public func nextReset(after date: Date) -> Date {
        let todayReset = resetInstant(on: date)
        if date < todayReset {
            return todayReset
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return resetInstant(on: tomorrow)
    }

    /// Clock time only, such as "4:00 AM". The reset is always within 24 hours.
    public func resetClockText(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: nextReset(after: date))
    }

    private func resetInstant(on date: Date) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        parts.nanosecond = 0
        parts.timeZone = calendar.timeZone
        if let exact = calendar.date(from: parts) {
            return exact
        }
        // Spring-forward gap: that minute does not exist. Use the next hour.
        parts.hour = min(23, hour + 1)
        parts.minute = 0
        return calendar.date(from: parts) ?? date
    }
}
