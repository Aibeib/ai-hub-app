import Foundation

/// Smart relative timestamp formatter used across the chat surface.
///
/// Rules:
/// - < 60 seconds  → "just now"
/// - < 60 minutes  → "Nm ago"
/// - < 24 hours    → "Nh ago"
/// - yesterday     → "yesterday"
/// - < 7 days      → weekday name ("Tuesday")
/// - same year     → short date ("Jun 23")
/// - otherwise     → date with year ("Jun 23, 2025")
///
/// Uses an injected clock so the same input produces deterministic output in tests.
public struct RelativeTimeFormatter: Sendable {
    private let clock: any Clock
    private let calendar: Calendar
    private let weekdayFormatter: DateFormatter
    private let monthDayFormatter: DateFormatter
    private let fullDateFormatter: DateFormatter

    public init(clock: any Clock = SystemClock(), calendar: Calendar = .current, locale: Locale = .current) {
        self.clock = clock
        var cal = calendar
        cal.locale = locale
        self.calendar = cal

        let weekday = DateFormatter()
        weekday.locale = locale
        weekday.dateFormat = "EEEE"
        self.weekdayFormatter = weekday

        let monthDay = DateFormatter()
        monthDay.locale = locale
        monthDay.setLocalizedDateFormatFromTemplate("MMM d")
        self.monthDayFormatter = monthDay

        let full = DateFormatter()
        full.locale = locale
        full.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        self.fullDateFormatter = full
    }

    public func string(from date: Date) -> String {
        let now = clock.now
        let interval = now.timeIntervalSince(date)

        // Future dates and "very recent" both collapse to "just now"
        if interval < 60 {
            return "just now"
        }

        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        }

        if interval < 86_400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }

        if calendar.isDate(date, inSameDayAs: now.addingTimeInterval(-86_400)) {
            return "yesterday"
        }

        if interval < 7 * 86_400 {
            return weekdayFormatter.string(from: date)
        }

        let nowComponents = calendar.dateComponents([.year], from: now)
        let dateComponents = calendar.dateComponents([.year], from: date)
        if nowComponents.year == dateComponents.year {
            return monthDayFormatter.string(from: date)
        }

        return fullDateFormatter.string(from: date)
    }
}
