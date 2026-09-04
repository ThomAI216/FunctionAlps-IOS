import Foundation

/// The notification map — what the phone schedules, from the member's preferences and today's state.
/// Pure and tested: the scheduler only turns this plan into UNNotificationRequests.
///
/// Local (this file) · Server (`push-send` on CM OS: practitioner message · approved report · care-plan
/// change · a meal that needs input). Rule: a reminder is never scheduled for something already done.
enum NotificationPlanner {
    enum Kind: String, Sendable, CaseIterable {
        case morningCheckin = "checkin.morning"
        case middayCheckin = "checkin.midday"
        case eveningCheckin = "checkin.evening"
        case lunchNotLogged = "meal.lunch"
        case dinnerNotLogged = "meal.dinner"
        case mealReaction = "meal.reaction"
        case weeklySummary = "weekly"
        case wearableStale = "wearable.stale"
    }

    struct Planned: Sendable, Equatable, Identifiable {
        let id: String            // stable: "<kind>.<day>" or "meal.reaction.<mealId>"
        let kind: Kind
        let fireAt: Date
        let title: String
        let body: String
        let route: String         // functionalps://…
        let threadId: String
    }

    /// What the plan needs to know about today (and the recent days).
    struct State: Sendable, Equatable {
        var now: Date
        var momentsDone: Set<MomentSlot> = []
        /// Meals logged today, by logged-at.
        var mealsToday: [Date] = []
        /// Meals logged in the last 4 hours that have no reaction yet: (id, loggedAt).
        var unratedRecentMeals: [(id: String, loggedAt: Date)] = []
        var appleHealthConnected = false
        var appleHealthLastSync: Date?

        static func == (a: State, b: State) -> Bool {
            a.now == b.now && a.momentsDone == b.momentsDone && a.mealsToday == b.mealsToday && a.appleHealthConnected == b.appleHealthConnected
                && a.appleHealthLastSync == b.appleHealthLastSync && a.unratedRecentMeals.map(\.id) == b.unratedRecentMeals.map(\.id)
        }
    }

    static let reactionDelay: TimeInterval = 2.5 * 3600
    static let horizonDays = 7

    /// The full plan for the next `horizonDays` days (today's already-done items dropped, past times dropped).
    static func plan(prefs: NotificationPrefs, state: State, calendar: Calendar = .current) -> [Planned] {
        var out: [Planned] = []
        let now = state.now
        let today = calendar.startOfDay(for: now)

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayKey = ISO8601.dayString(day, calendar: calendar)
            let isToday = offset == 0

            func at(_ hhmm: String) -> Date? {
                guard let p = NotificationPrefs.parse(hhmm) else { return nil }
                return calendar.date(bySettingHour: p.hour, minute: p.minute, second: 0, of: day)
            }
            func add(_ kind: Kind, _ fireAt: Date?, _ title: String, _ body: String, _ route: String) {
                guard let fireAt, fireAt > now else { return }
                out.append(Planned(id: "\(kind.rawValue).\(dayKey)", kind: kind, fireAt: fireAt, title: title, body: body, route: route, threadId: kind.rawValue))
            }

            // Check-in moments — skipped today when that moment is already done.
            if prefs.morningEnabled, !(isToday && state.momentsDone.contains(.morning)) {
                add(.morningCheckin, at(prefs.morningTime),
                    String(localized: "notif.morning.title", defaultValue: "Good morning ☀️"),
                    String(localized: "notif.morning.body", defaultValue: "How did you sleep? Two taps set today's baseline."),
                    "functionalps://checkin/morning")
            }
            if prefs.middayEnabled, !(isToday && state.momentsDone.contains(.midday)) {
                add(.middayCheckin, at(prefs.middayTime),
                    String(localized: "notif.midday.title", defaultValue: "Midday check-in"),
                    String(localized: "notif.midday.body", defaultValue: "Energy, focus, digestion — how is the afternoon starting?"),
                    "functionalps://checkin/midday")
            }
            if prefs.eveningEnabled, !(isToday && state.momentsDone.contains(.evening)) {
                add(.eveningCheckin, at(prefs.eveningTime),
                    String(localized: "notif.evening.title", defaultValue: "Your evening check-in 🌙"),
                    String(localized: "notif.evening.body", defaultValue: "Two minutes before bed sharpens tomorrow's picture."),
                    "functionalps://checkin/evening")
            }

            // Meals not logged — lunch 13:30 (window 11:00–13:30), dinner 20:15 (window 17:30–20:15); skipped when a meal fell in the window.
            if prefs.mealRemindersEnabled {
                func logged(between fromH: Int, _ fromM: Int, and toH: Int, _ toM: Int) -> Bool {
                    guard isToday, let from = calendar.date(bySettingHour: fromH, minute: fromM, second: 0, of: day),
                          let to = calendar.date(bySettingHour: toH, minute: toM, second: 0, of: day) else { return false }
                    return state.mealsToday.contains { $0 >= from && $0 <= to }
                }
                if !logged(between: 11, 0, and: 13, 30) {
                    add(.lunchNotLogged, at("13:30"),
                        String(localized: "notif.lunch.title", defaultValue: "No lunch photo yet?"),
                        String(localized: "notif.lunch.body", defaultValue: "A quick snap now keeps today's picture whole."),
                        "functionalps://food")
                }
                if !logged(between: 17, 30, and: 20, 15) {
                    add(.dinnerNotLogged, at("20:15"),
                        String(localized: "notif.dinner.title", defaultValue: "Dinner not logged"),
                        String(localized: "notif.dinner.body", defaultValue: "Photograph or describe it — 20 seconds."),
                        "functionalps://food")
                }
            }

            // Weekly summary — Sunday 18:00.
            if prefs.weeklySummaryEnabled, calendar.component(.weekday, from: day) == 1 {
                add(.weeklySummary, at("18:00"),
                    String(localized: "notif.weekly.title", defaultValue: "Your week at a glance"),
                    String(localized: "notif.weekly.body", defaultValue: "Seven days of meals, check-ins and nights — see what moved."),
                    "functionalps://trends")
            }
        }

        // 2.5 h after each recent meal with no reaction yet.
        if prefs.postMealFollowupEnabled {
            for meal in state.unratedRecentMeals {
                let fireAt = meal.loggedAt.addingTimeInterval(reactionDelay)
                guard fireAt > now else { continue }
                out.append(Planned(id: "\(Kind.mealReaction.rawValue).\(meal.id)", kind: .mealReaction, fireAt: fireAt,
                                   title: String(localized: "notif.reaction.title", defaultValue: "How do you feel after that meal?"),
                                   body: String(localized: "notif.reaction.body", defaultValue: "Energy, digestion, bloating — 10 seconds, and it teaches the pattern."),
                                   route: "functionalps://meal/\(meal.id)?rate=1", threadId: Kind.mealReaction.rawValue))
            }
        }

        // Apple Health silent for 3 days.
        if state.appleHealthConnected, let last = state.appleHealthLastSync {
            let fireAt = last.addingTimeInterval(3 * 86_400)
            if fireAt > now {
                out.append(Planned(id: "\(Kind.wearableStale.rawValue).\(ISO8601.dayString(fireAt, calendar: calendar))", kind: .wearableStale, fireAt: fireAt,
                                   title: String(localized: "notif.stale.title", defaultValue: "Apple Health hasn't synced for 3 days"),
                                   body: String(localized: "notif.stale.body", defaultValue: "Open FunctionAlps once so your nights and steps catch up."),
                                   route: "functionalps://devices", threadId: Kind.wearableStale.rawValue))
            }
        }

        return out.sorted { $0.fireAt < $1.fireAt }
    }

    /// Quiet hours: a reminder that would fire inside them moves to the end of the window (same day, or next morning).
    static func respectingQuietHours(_ plan: [Planned], prefs: NotificationPrefs, calendar: Calendar = .current) -> [Planned] {
        guard prefs.quietHoursEnabled, let start = NotificationPrefs.parse(prefs.quietStart), let end = NotificationPrefs.parse(prefs.quietEnd) else { return plan }
        let startMin = start.hour * 60 + start.minute, endMin = end.hour * 60 + end.minute
        return plan.map { p in
            let m = calendar.component(.hour, from: p.fireAt) * 60 + calendar.component(.minute, from: p.fireAt)
            let inside = startMin <= endMin ? (m >= startMin && m < endMin) : (m >= startMin || m < endMin)
            guard inside else { return p }
            var day = calendar.startOfDay(for: p.fireAt)
            if startMin > endMin, m >= startMin, let next = calendar.date(byAdding: .day, value: 1, to: day) { day = next }
            guard let moved = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: day) else { return p }
            return Planned(id: p.id, kind: p.kind, fireAt: moved, title: p.title, body: p.body, route: p.route, threadId: p.threadId)
        }
    }
}
