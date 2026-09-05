import Foundation

/// The check-in streak shown on the Home carousel: consecutive calendar days, ending today (or yesterday
/// when today is not done yet), with at least one functional check-in saved. Pure, from the 14-day
/// history rows Home already reads — never a server score.
enum CheckinStreak {
    /// - Parameters:
    ///   - history: the day rows (any order); a day counts when `functionalCompletedAt` is set.
    ///   - todayDone: today's moments exist (the day row may lag the moment write by a refresh).
    ///   - today: `YYYY-MM-DD` in the member's calendar.
    static func days(history: [DailyCheckin], todayDone: Bool, today: String, calendar: Calendar = .current) -> Int {
        var done = Set(history.filter(\.isFunctionalDone).map(\.day))
        if todayDone { done.insert(today) }
        guard var cursor = Self.date(today, calendar: calendar) else { return 0 }
        // Today not yet done does not break the chain — the streak is "as of last night" until it is.
        if !done.contains(today) {
            guard let y = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = y
        }
        var count = 0
        while done.contains(ISO8601.dayString(cursor, calendar: calendar)) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    /// `YYYY-MM-DD` → midnight in the member's calendar.
    static func date(_ day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
