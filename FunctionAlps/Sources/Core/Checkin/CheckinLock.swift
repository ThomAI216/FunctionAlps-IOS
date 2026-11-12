import Foundation

/// Lock after save (owner-validated 2026-11-12): once a check-in has been saved for a day, its controls are read-only. A
/// tap on a locked control asks "Change your check-in for <weekday d MMM>?"; Change unlocks the screen for editing, and
/// saving again locks it. Pure state, no UI.
struct CheckinLock: Sendable, Equatable {
    /// A check-in already exists for this day (loaded, or just saved).
    private(set) var saved = false
    /// The member said "Change" and has not saved since.
    private(set) var unlocked = false

    init(saved: Bool = false) { self.saved = saved }

    /// Controls are read-only.
    var isLocked: Bool { saved && !unlocked }

    /// A tap landed on a locked control: the screen must ask before anything changes.
    var tapNeedsConfirmation: Bool { isLocked }

    /// A check-in for this day was found (opening the screen on a saved day).
    mutating func loaded(saved: Bool) {
        self.saved = saved
        unlocked = false
    }

    /// "Change" was confirmed. Does nothing on a day with no saved check-in (nothing is locked there).
    mutating func unlock() {
        if saved { unlocked = true }
    }

    /// A save succeeded: the screen is read-only again.
    mutating func didSave() {
        saved = true
        unlocked = false
    }
}

/// The day as the member reads it: "Thursday 12 Nov" (the order and the words follow the app's language).
enum CheckinDayLabel {
    /// `dayString` is `YYYY-MM-DD`. Nil when it is not a day.
    static func text(forDay dayString: String, locale: Locale = .current, calendar: Calendar = .current) -> String? {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return formatter.string(from: date)
    }

    /// The day before `dayString`, as `YYYY-MM-DD`.
    static func previousDay(of dayString: String, calendar: Calendar = .current) -> String? {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = calendar.date(from: components), let previous = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        return ISO8601.dayString(previous, calendar: calendar)
    }
}
