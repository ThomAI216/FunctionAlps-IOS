import Foundation

/// One dot of a habit's streak.
struct HabitDot: Sendable, Equatable, Identifiable {
    enum State: Sendable, Equatable {
        case done
        case missed
        /// A day to come, or today before the tick.
        case notYet
        /// A day the habit does not run (before it starts, after it ends).
        case outside
    }

    let day: Int
    let state: State
    let isToday: Bool
    var id: Int { day }
}

/// Streaks are formatting of what was recorded (rule 9): the days a member ticked a track action (`track_activity`,
/// kind `action`), counted in the track's own day numbers. No health figure is computed here.
enum HabitStreak {
    static let window = 14

    /// The first and last track day an action appears on (the practice lists a running action on every day it runs).
    static func span(of key: String, in days: [TrackDay]) -> (first: Int, last: Int)? {
        let on = days.filter { $0.actions.contains { $0.key == key } }.map(\.day)
        guard let first = on.min(), let last = on.max() else { return nil }
        return (first, last)
    }

    /// The days an action was ticked.
    static func doneDays(key: String, activity: Set<TrackActivityItem>) -> Set<Int> {
        Set(activity.filter { $0.kind == .action && $0.itemKey == key }.map(\.day))
    }

    /// Consecutive days done, up to today. A missed day breaks it; today not ticked yet does not (the run so far
    /// stands until the day is over). Only days the habit runs count.
    static func current(done: Set<Int>, first: Int, last: Int?, today: Int) -> Int {
        var day = min(today, last ?? today)
        if day == today, !done.contains(day) { day -= 1 }
        var run = 0
        while day >= first, done.contains(day) { run += 1; day -= 1 }
        return run
    }

    /// The days shown: 1…14 while the member is inside the track, else the 14 days ending today.
    static func windowDays(today: Int) -> ClosedRange<Int> {
        today <= window ? 1...window : (today - window + 1)...today
    }

    static func dots(done: Set<Int>, first: Int, last: Int?, today: Int) -> [HabitDot] {
        windowDays(today: today).map { day in
            let runs = day >= first && day <= (last ?? Int.max)
            let state: HabitDot.State
            if !runs { state = .outside }
            else if day > today { state = .notYet }
            else if done.contains(day) { state = .done }
            else { state = day == today ? .notYet : .missed }
            return HabitDot(day: day, state: state, isToday: day == today)
        }
    }

    /// "No streak card on the habit's first day."
    static func showsStreak(first: Int, today: Int) -> Bool { today > first }
}
