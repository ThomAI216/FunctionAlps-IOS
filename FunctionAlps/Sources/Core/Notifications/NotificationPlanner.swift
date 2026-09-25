import Foundation

/// The notification map — what the phone schedules, from the member's preferences and today's state.
/// Pure and tested: the scheduler only turns this plan into UNNotificationRequests.
///
/// Local (this file) · Server (`push-send` on CM OS: practitioner message · approved report · care-plan
/// change · a meal that needs input). Rule: a reminder is never scheduled for something already done.
///
/// Meals follow the member's own schedule (`member_meal_schedule`, docs/MEAL_RHYTHM_SPEC.md): one reminder
/// per switched-on slot, at the member's time, only while that meal is not logged — a cue to photograph the
/// plate before the first bite, never a comment on the time.
enum NotificationPlanner {
    enum Kind: String, Sendable, CaseIterable {
        case morningCheckin = "checkin.morning"
        /// Retired — never planned. The case stays so `apply()` still recognises (and clears) the
        /// midday requests a previous build left pending on the phone.
        case middayCheckin = "checkin.midday"
        case eveningCheckin = "checkin.evening"
        case breakfast = "meal.breakfast"
        case morningSnack = "meal.morning_snack"
        /// Same raw value as the fixed 13:30 "lunch not logged" nudge it replaces, so those pending requests
        /// reconcile instead of doubling up.
        case lunch = "meal.lunch"
        case afternoonSnack = "meal.afternoon_snack"
        /// Same raw value as the fixed 20:15 "dinner not logged" nudge it replaces.
        case dinner = "meal.dinner"
        case mealReaction = "meal.reaction"
        case weeklySummary = "weekly"
        case wearableStale = "wearable.stale"

        static func meal(_ slot: MealSlot) -> Kind {
            switch slot {
            case .breakfast: .breakfast
            case .morningSnack: .morningSnack
            case .lunch: .lunch
            case .afternoonSnack: .afternoonSnack
            case .dinner: .dinner
            }
        }

        var isMealSlot: Bool {
            switch self {
            case .breakfast, .morningSnack, .lunch, .afternoonSnack, .dinner: true
            default: false
            }
        }

        /// Who keeps their time when two reminders would land within `minGap` (lower keeps it).
        var priority: Int {
            switch self {
            case .morningCheckin, .middayCheckin, .eveningCheckin: 0
            case .breakfast, .morningSnack, .lunch, .afternoonSnack, .dinner: 1
            case .mealReaction: 2
            case .weeklySummary: 3
            case .wearableStale: 4
            }
        }
    }

    struct Planned: Sendable, Equatable, Identifiable {
        let id: String            // stable: "<kind>.<day>" or "meal.reaction.<mealId>"
        let kind: Kind
        let fireAt: Date
        let title: String
        let body: String
        let route: String         // functionalps://…
        let threadId: String

        func moved(to date: Date) -> Planned {
            Planned(id: id, kind: kind, fireAt: date, title: title, body: body, route: route, threadId: threadId)
        }
    }

    /// A meal logged today: when, and the member's word for it (nil for an old row with no type).
    struct LoggedMeal: Sendable, Equatable {
        let at: Date
        let type: MealLog.MealType?
    }

    /// What the plan needs to know about today (and the recent days).
    struct State: Sendable, Equatable {
        var now: Date
        var momentsDone: Set<MomentSlot> = []
        /// Meals logged today.
        var mealsToday: [LoggedMeal] = []
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
    /// Meal slots are planned 4 days ahead, not 7: up to five a day would crowd out iOS's 64 pending requests,
    /// and every foreground re-plans anyway — a member who hasn't opened the app for four days stops getting them.
    static let mealHorizonDays = 4
    /// iOS keeps at most 64 pending local notifications; stay under it with room for `mealLogged` additions.
    static let maxPending = 60
    /// No two FunctionAlps notifications closer than this.
    static let minGap: TimeInterval = 20 * 60
    /// A reminder pushed later than this by spacing is dropped instead: it would no longer mean its moment.
    static let maxShift: TimeInterval = 40 * 60

    /// The full plan for the next `horizonDays` days (today's already-done items dropped, past times dropped).
    /// `schedule` nil = not known yet (offline launch): no meal slot is planned, and the caller keeps whatever
    /// meal reminders are already pending rather than guessing.
    static func plan(prefs: NotificationPrefs, schedule: MealSchedule? = .defaults, state: State, calendar: Calendar = .current) -> [Planned] {
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

            // TWO check-in moments, and only two: the night behind you, then the day you lived.
            // Skipped today when that moment is already done. Midday is never planned (retired).
            if prefs.morningEnabled, !(isToday && state.momentsDone.contains(.morning)) {
                add(.morningCheckin, at(prefs.morningTime),
                    String(localized: "notif.morning.title", defaultValue: "Good morning ☀️"),
                    String(localized: "notif.morning.body", defaultValue: "How did you sleep, and what does today need? Under a minute."),
                    "functionalps://checkin/morning")
            }
            if prefs.eveningEnabled, !(isToday && state.momentsDone.contains(.evening)) {
                add(.eveningCheckin, at(prefs.eveningTime),
                    String(localized: "notif.evening.title", defaultValue: "Look back on your day 🌙"),
                    String(localized: "notif.evening.body", defaultValue: "Energy, focus, mood and digestion — how did the day actually go?"),
                    "functionalps://checkin/evening")
            }

            // The member's meal slots, at their times, skipped today once that meal is logged.
            if prefs.mealRemindersEnabled, let schedule, offset < mealHorizonDays {
                let done: Set<MealSlot> = isToday
                    ? Set(state.mealsToday.map { schedule.slot(forMealAt: $0.at, type: $0.type, calendar: calendar) })
                    : []
                for entry in schedule.enabledEntries(weekday: MealSchedule.isoWeekday(of: day, calendar: calendar)) where !done.contains(entry.slot) {
                    let copy = mealCopy(entry.slot)
                    add(.meal(entry.slot), at(entry.remindAt), copy.title, copy.body, "functionalps://food")
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

    /// Quiet hours: a reminder that would fire inside them moves to the end of the window (same day, or next
    /// morning) — except a meal reminder, which is dropped: "Dinner?" at 07:30 the next day is worse than nothing.
    static func respectingQuietHours(_ plan: [Planned], prefs: NotificationPrefs, calendar: Calendar = .current) -> [Planned] {
        guard prefs.quietHoursEnabled, let start = NotificationPrefs.parse(prefs.quietStart), let end = NotificationPrefs.parse(prefs.quietEnd) else { return plan }
        let startMin = start.hour * 60 + start.minute, endMin = end.hour * 60 + end.minute
        return plan.compactMap { (p: Planned) -> Planned? in
            let m = calendar.component(.hour, from: p.fireAt) * 60 + calendar.component(.minute, from: p.fireAt)
            let inside = startMin <= endMin ? (m >= startMin && m < endMin) : (m >= startMin || m < endMin)
            guard inside else { return p }
            if p.kind.isMealSlot { return nil }
            var day = calendar.startOfDay(for: p.fireAt)
            if startMin > endMin, m >= startMin, let next = calendar.date(byAdding: .day, value: 1, to: day) { day = next }
            guard let moved = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: day) else { return p }
            return p.moved(to: moved)
        }
    }

    /// No two reminders within `minGap`: the higher priority keeps its time (check-in, then meal, then
    /// reaction, then weekly, then stale sync; the earlier one on a tie), the other moves just past it — and is
    /// dropped if that is more than `maxShift` late. The morning check-in and a default breakfast both sit at 08:00.
    static func spaced(_ plan: [Planned]) -> [Planned] {
        var placed: [Planned] = []
        for p in plan.sorted(by: { ($0.kind.priority, $0.fireAt, $0.id) < ($1.kind.priority, $1.fireAt, $1.id) }) {
            var fireAt = p.fireAt
            while let clash = placed.first(where: { abs($0.fireAt.timeIntervalSince(fireAt)) < minGap }) {
                fireAt = clash.fireAt.addingTimeInterval(minGap)
            }
            guard fireAt.timeIntervalSince(p.fireAt) <= maxShift else { continue }
            placed.append(fireAt == p.fireAt ? p : p.moved(to: fireAt))
        }
        return placed.sorted { $0.fireAt < $1.fireAt }
    }

    /// What the phone actually schedules: quiet hours, then spacing, then the nearest `maxPending`.
    static func finalized(_ plan: [Planned], prefs: NotificationPrefs, calendar: Calendar = .current) -> [Planned] {
        Array(spaced(respectingQuietHours(plan, prefs: prefs, calendar: calendar)).prefix(maxPending))
    }

    /// Neutral on purpose: a cue to photograph before the first bite, never a word about the time.
    private static func mealCopy(_ slot: MealSlot) -> (title: String, body: String) {
        let plate = String(localized: "notif.meal.body", defaultValue: "Snap your plate before you start.")
        let snack = String(localized: "notif.snack.body", defaultValue: "A quick photo keeps the day whole.")
        switch slot {
        case .breakfast: return (String(localized: "notif.breakfast.title", defaultValue: "Breakfast?"), plate)
        case .morningSnack: return (String(localized: "notif.morningSnack.title", defaultValue: "A morning snack?"), snack)
        case .lunch: return (String(localized: "notif.mealLunch.title", defaultValue: "Lunch?"), plate)
        case .afternoonSnack: return (String(localized: "notif.afternoonSnack.title", defaultValue: "An afternoon snack?"), snack)
        case .dinner: return (String(localized: "notif.mealDinner.title", defaultValue: "Dinner?"), plate)
        }
    }
}
