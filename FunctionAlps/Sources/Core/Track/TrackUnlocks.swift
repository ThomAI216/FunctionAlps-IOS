import Foundation

/// What a member on the Foundation Track unlocks by using the app (Thomas, 2026-11-06: "this will incentivize them").
/// Trends opens after 3 days in a row of using the app; Food opens with the first meal logged. A day "uses the
/// app" when it has a functional check-in or a meal logged. Once open, a tab stays open: the rule looks for any run
/// of 3 days in the history, not only the run that ends today. Pure; the dates are the member's calendar days.
enum TrackUnlocks {
    /// Days in a row that open Trends.
    static let trendsStreak = 3

    /// The days the member used the app (`YYYY-MM-DD`): a functional check-in, or a meal logged that day.
    static func activeDays(checkins: [DailyCheckin], mealDates: [Date], calendar: Calendar = .current) -> Set<String> {
        var days = Set(checkins.filter(\.isFunctionalDone).map(\.day))
        for date in mealDates { days.insert(ISO8601.dayString(date, calendar: calendar)) }
        return days
    }

    /// The longest run of consecutive days in `days`.
    static func longestRun(_ days: Set<String>, calendar: Calendar = .current) -> Int {
        let dates = days.compactMap { CheckinStreak.date($0, calendar: calendar) }.sorted()
        var best = 0, run = 0
        var previous: Date?
        for date in dates {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: date) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = date
        }
        return best
    }

    /// The run as of today: ending today, or yesterday while today has nothing yet (today does not break it).
    static func currentRun(_ days: Set<String>, today: String, calendar: Calendar = .current) -> Int {
        guard var cursor = CheckinStreak.date(today, calendar: calendar) else { return 0 }
        if !days.contains(today), let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) { cursor = yesterday }
        var count = 0
        while days.contains(ISO8601.dayString(cursor, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func trendsOpen(_ days: Set<String>, calendar: Calendar = .current) -> Bool { longestRun(days, calendar: calendar) >= trendsStreak }

    static func foodOpen(mealCount: Int) -> Bool { mealCount > 0 }
}
