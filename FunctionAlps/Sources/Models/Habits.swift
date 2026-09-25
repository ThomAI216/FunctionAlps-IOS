import Foundation

// The Habit Loop on the phone — the clinician's prescribed habits, checked off day by day.
//
// The model: THE CLINICIAN DECIDES, THE SOFTWARE REVEALS (Expo `docs/prd/2026-08-16-habit-loop-design.md`).
// A habit reaches a member only when its care-plan item is patient-visible and approved — enforced by RLS on
// `habits`, not by anything here. The phone's only autonomous act is arithmetic: which habits are due today
// (their RRULE), which are done (a completion row), how long the run is. Nothing below reads a health signal.
//
// `HabitEngine` is a line-for-line port of the Expo pure modules (`lib/plan/{slots,streaks,today,derive,
// plan-headline,day-math}.ts`, `lib/report/rrule-lite.ts`): explicit `YYYY-MM-DD` days, no clock, no I/O.

/// The three moments of the day a habit can belong to; a habit with no slot is "Anytime".
enum HabitSlot: String, Sendable, Hashable, CaseIterable {
    case morning, midday, evening

    static let order: [HabitSlot] = [.morning, .midday, .evening]
    var rank: Int { Self.order.firstIndex(of: self) ?? 0 }

    /// Which slot "now" falls in (patient-local hour): `<11` morning, 11–16 midday, `>=17` evening.
    static func current(hour: Int) -> HabitSlot {
        if hour < 11 { return .morning }
        if hour < 17 { return .midday }
        return .evening
    }

    var label: String {
        switch self {
        case .morning: String(localized: "plan.slot.morning", defaultValue: "Morning")
        case .midday: String(localized: "plan.slot.midday", defaultValue: "Midday")
        case .evening: String(localized: "plan.slot.evening", defaultValue: "Evening")
        }
    }
}

/// One `habits` row the member may read (RLS: own, not cancelled, and — when prescribed — its item approved).
struct HabitRow: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let carePlanItemId: String?
    let title: String
    let description: String?
    /// RFC-5545 RRULE, `FREQ=DAILY` / `FREQ=WEEKLY;BYDAY=…` (with or without the `RRULE:` prefix); nil = daily.
    let frequencyRule: String?
    /// `active` · `paused` · `completed` (cancelled rows never arrive).
    let status: String
    /// `prescribed` (the clinician's, behind a care-plan item) or `self_initiated` (the member's own).
    let source: String
    let pillar: String?
    /// `morning` · `midday` · `evening`; nil or unknown = Anytime.
    let slot: String?
    /// Sequencing: visible today only once this other habit is done today (broken chains fail SAFE → visible).
    let appearsAfterHabitId: String?
    let easyTitle: String?
    let easyDescription: String?
    let revTitle: String?
    let revDescription: String?
    /// ISO timestamp — nothing is due before the habit existed.
    let createdAt: String

    var slotValue: HabitSlot? { slot.flatMap(HabitSlot.init(rawValue:)) }
    var isActive: Bool { status == "active" }
    var isSelfInitiated: Bool { source == "self_initiated" }
    /// `YYYY-MM-DD` of `createdAt`.
    var createdDay: String { String(createdAt.prefix(10)) }
}

/// One `habit_completions` row (the member's own; `completion_date` is the live column).
struct HabitCompletionRow: Decodable, Sendable, Equatable {
    let id: String
    let habitId: String
    let completionDate: String
    var day: String { String(completionDate.prefix(10)) }
}

/// The active `care_plans` header — patient-renderable columns only.
struct HabitPlanHeader: Decodable, Sendable, Equatable {
    let id: String
    let title: String?
    let startDate: String?
    /// Clinician-authored, patient-facing ("Getting towards more stamina") — the headline ladder's first rung.
    let objectiveLine: String?
}

/// One `care_plan_phases` row, patient-renderable columns only (`gate_criteria` is clinician prose, never read).
struct HabitPlanPhase: Decodable, Sendable, Equatable {
    let phaseKey: String
    let weekStart: Int
    let weekEnd: Int?
    let title: String?
    let summary: String?
}

/// Everything the Home card needs for one day, in one value.
struct HabitPlan: Sendable, Equatable {
    /// `YYYY-MM-DD` — the member's own day.
    let day: String
    let header: HabitPlanHeader?
    let phases: [HabitPlanPhase]
    /// Own habits, not cancelled, in creation order.
    let habits: [HabitRow]
    /// The trailing `HabitEngine.completionsLookbackDays` of completions, today included.
    var completions: [HabitCompletionRow]

    var activeHabits: [HabitRow] { habits.filter(\.isActive) }
}

/// One line of the Home card: a habit due today, as the member acts on it.
struct HabitAction: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String?
    let slot: HabitSlot?
    /// Today's completion row when done — the undo handle; nil = not done.
    let completionId: String?
    /// Consecutive due days done, today included when done (≥ 2 is worth showing).
    let streak: Int

    var done: Bool { completionId != nil }
}

/// Pure arithmetic over the rows. Every date is an explicit `YYYY-MM-DD`; there is no clock in here.
enum HabitEngine {
    /// Trailing completion history fetched for streaks (the Expo `COMPLETIONS_LOOKBACK_DAYS`).
    static let completionsLookbackDays = 70
    /// How many rows the Home card shows (the Expo `HOME_ACTION_LIMIT`).
    static let homeActionLimit = 3
    /// One day in a row is a day, not a streak (the Expo `STREAK_BADGE_MIN`).
    static let streakBadgeMin = 2
    /// Hard cap on the backward walk so pathological rules stay bounded.
    static let streakWalkCapDays = 365
    /// Hard cap on the sequencing chain walk so cyclic data stays bounded.
    static let sequenceHopCap = 20

    // MARK: Day math (UTC midnight, like the Expo `day-math.ts` — a day key is a key, not a moment)

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func date(_ day: String) -> Date? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func dayString(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `day` shifted by `delta` calendar days (negative = earlier). An unparseable day comes back unchanged.
    static func shift(_ day: String, by delta: Int) -> String {
        guard let d = date(day), let shifted = utc.date(byAdding: .day, value: delta, to: d) else { return day }
        return dayString(shifted)
    }

    /// Whole days from `a` to `b` (positive when `b` is later); nil when either does not parse.
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let da = date(a), let db = date(b) else { return nil }
        return utc.dateComponents([.day], from: da, to: db).day
    }

    /// 0 = Sunday … 6 = Saturday (the RRULE BYDAY codes).
    static func weekday(_ day: String) -> Int? {
        date(day).map { utc.component(.weekday, from: $0) - 1 }
    }

    // MARK: RRULE (the Expo `rrule-lite.ts`, line for line)

    struct DueRule: Equatable, Sendable {
        enum Freq: Sendable { case daily, weekly, unknown }
        var freq: Freq = .unknown
        var interval = 1
        /// 0 (Sun) – 6 (Sat); empty = unspecified.
        var byday: [Int] = []
    }

    private static let bydayCode: [String: Int] = ["SU": 0, "MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6]

    /// `FREQ=DAILY` and `FREQ=WEEKLY` with `BYDAY` / `INTERVAL` — everything the clinical push pipeline emits.
    /// Anything else parses as `unknown`, which counts as due every day: a prescribed action is never hidden
    /// by a rule the phone cannot read.
    static func parseRule(_ rule: String?) -> DueRule {
        var out = DueRule()
        guard let rule, !rule.isEmpty else { return out }
        let body = rule.hasPrefix("RRULE:") || rule.hasPrefix("rrule:") ? String(rule.dropFirst(6)) : rule
        for part in body.trimmingCharacters(in: .whitespaces).split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            let key = kv.first ?? "", value = kv.count > 1 ? kv[1] : ""
            switch key {
            case "FREQ": out.freq = value == "DAILY" ? .daily : value == "WEEKLY" ? .weekly : .unknown
            case "INTERVAL": if let n = Int(value), n >= 1 { out.interval = n }
            case "BYDAY": out.byday = value.split(separator: ",").compactMap { bydayCode[String($0)] }
            default: break
            }
        }
        return out
    }

    /// Is a habit with this rule due on `day`? Nothing is due before `start` (the habit's creation day).
    static func isDue(_ rule: String?, on day: String, start: String?) -> Bool {
        let r = parseRule(rule)
        let sinceStart = start.flatMap { daysBetween($0, day) }
        if let sinceStart, sinceStart < 0 { return false }
        switch r.freq {
        case .unknown: return true
        case .daily:
            if r.interval > 1, let sinceStart { return sinceStart % r.interval == 0 }
            return true
        case .weekly:
            guard let dow = weekday(day) else { return true }
            let dayOk: Bool
            if !r.byday.isEmpty { dayOk = r.byday.contains(dow) }
            else if let start, let startDow = weekday(start) { dayOk = dow == startDow }
            else { dayOk = true }
            guard dayOk else { return false }
            if r.interval > 1, let sinceStart { return (sinceStart / 7) % r.interval == 0 }
            return true
        }
    }

    // MARK: Completions

    /// Habit ids with a completion on `day`.
    static func doneIds(_ completions: [HabitCompletionRow], on day: String) -> Set<String> {
        Set(completions.filter { $0.day == day }.map(\.habitId))
    }

    /// The completion row for a habit on a day — undo needs the row, not a re-query.
    static func completionId(_ completions: [HabitCompletionRow], habit: String, on day: String) -> String? {
        completions.first { $0.habitId == habit && $0.day == day }?.id
    }

    /// Consecutive DUE days done, walking back from today. Non-due days never break a streak, days before the
    /// habit existed are not due, and today due-but-undone is PENDING, not a miss: the walk starts at yesterday.
    static func currentStreak(_ habit: HabitRow, completions: [HabitCompletionRow], today: String) -> Int {
        let done = Set(completions.filter { $0.habitId == habit.id }.map(\.day))
        let start = habit.createdDay
        var streak = 0
        if isDue(habit.frequencyRule, on: today, start: start), done.contains(today) { streak += 1 }
        for back in 1...streakWalkCapDays {
            let day = shift(today, by: -back)
            if day < start { break }
            if !isDue(habit.frequencyRule, on: day, start: start) { continue }
            if !done.contains(day) { break }
            streak += 1
        }
        return streak
    }

    // MARK: Sequencing (the Expo `slots.visibleToday`)

    /// A habit with `appearsAfterHabitId` shows only once that habit is done today. Broken chains fail SAFE:
    /// a dangling reference, a cycle, or a chain longer than the cap all read as visible — bad data never hides
    /// a prescribed habit. An intact chain whose predecessor is undone is genuinely pending → hidden.
    static func visibleToday(_ habit: HabitRow, in habits: [HabitRow], doneIds: Set<String>) -> Bool {
        guard let afterId = habit.appearsAfterHabitId else { return true }
        let byId = Dictionary(habits.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        guard let first = byId[afterId] else { return true }
        if doneIds.contains(first.id) { return true }
        var visited: Set<String> = [habit.id, first.id]
        var current = first
        for _ in 0..<sequenceHopCap {
            guard let nextId = current.appearsAfterHabitId else { return false }
            if visited.contains(nextId) { return true }
            guard let next = byId[nextId] else { return false }
            visited.insert(nextId)
            current = next
        }
        return true
    }

    // MARK: Today

    /// The habits to act on today, in the order the Expo Home card shows them: the CURRENT moment's first,
    /// then Anytime, then the moments still ahead, then the earlier moments' undone ones (catch-up), then the
    /// earlier moments' done ones — so completed work never disappears. Only active habits due today, with
    /// sequencing applied. Stable: a row does not move when it is checked off.
    static func todayActions(_ plan: HabitPlan, hour: Int) -> [HabitAction] {
        let now = HabitSlot.current(hour: hour)
        let done = doneIds(plan.completions, on: plan.day)
        let due = plan.activeHabits.filter { isDue($0.frequencyRule, on: plan.day, start: $0.createdDay) }
        var current: [HabitAction] = [], anytime: [HabitAction] = []
        var later: [HabitSlot: [HabitAction]] = [:]
        var earlierUndone: [HabitAction] = [], earlierDone: [HabitAction] = []

        for habit in due where visibleToday(habit, in: plan.habits, doneIds: done) {
            let action = HabitAction(
                id: habit.id, title: habit.title, detail: habit.description, slot: habit.slotValue,
                completionId: completionId(plan.completions, habit: habit.id, on: plan.day),
                streak: currentStreak(habit, completions: plan.completions, today: plan.day)
            )
            guard let slot = action.slot else { anytime.append(action); continue }
            if slot == now { current.append(action) }
            else if slot.rank > now.rank { later[slot, default: []].append(action) }
            else if action.done { earlierDone.append(action) }
            else { earlierUndone.append(action) }
        }
        var out = current + anytime
        for slot in HabitSlot.order { out += later[slot] ?? [] }
        return out + earlierUndone + earlierDone
    }

    // MARK: The line above the habits (the Expo `plan-headline.ts`)

    /// `title` is clinical-voice and often auto-generated ("Care plan — 2026-08-15") — never a member's headline.
    static func isGenericPlanTitle(_ title: String?) -> Bool {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if t.range(of: #"^care\s*plan\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if t.range(of: #"^untitled"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if t.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// The week the member is in (1-based) — nil before the plan started or without a start date.
    static func planWeek(start: String?, today: String) -> Int? {
        guard let start, let days = daysBetween(start, today), days >= 0 else { return nil }
        return days / 7 + 1
    }

    /// The phase covering this week, when the clinician wrote phases.
    static func currentPhase(_ phases: [HabitPlanPhase], start: String?, today: String) -> HabitPlanPhase? {
        guard let week = planWeek(start: start, today: today) else { return nil }
        return phases.first { $0.weekStart <= week && (($0.weekEnd ?? Int.max) >= week) }
    }

    /// Pillars in tie-break order, so a headline never flickers between two equally weighted pillars.
    static let headlinePillarOrder = ["sleep", "nutrition", "exercise", "mind", "emotion", "recovery"]

    /// Descriptive, never promissory: each names what the person is PRACTISING. An outcome-shaped line
    /// ("Managing your bloating") may only ever come from the clinician's `objective_line`.
    static func pillarHeadline(_ pillar: String) -> String? {
        switch pillar {
        case "sleep": String(localized: "plan.headline.sleep", defaultValue: "Your evenings, one night at a time")
        case "nutrition": String(localized: "plan.headline.nutrition", defaultValue: "Eating steadier, day by day")
        case "exercise": String(localized: "plan.headline.exercise", defaultValue: "Moving a little every day")
        case "mind": String(localized: "plan.headline.mind", defaultValue: "A quieter head, day by day")
        case "emotion": String(localized: "plan.headline.emotion", defaultValue: "Room for how you feel")
        case "recovery": String(localized: "plan.headline.recovery", defaultValue: "Proper rest, on purpose")
        default: nil
        }
    }

    /// The headline, by a fixed ladder: the clinician's objective line → the current phase's title → the plan
    /// title when it isn't generic → a line describing the dominant pillar of the active habits → "the habits
    /// you chose" when every habit is the member's own → the neutral default.
    static func headline(_ plan: HabitPlan) -> String {
        if let objective = plan.header?.objectiveLine?.trimmingCharacters(in: .whitespacesAndNewlines), !objective.isEmpty { return objective }
        if let phase = currentPhase(plan.phases, start: plan.header?.startDate, today: plan.day)?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !phase.isEmpty { return phase }
        if let title = plan.header?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !isGenericPlanTitle(title) { return title }

        let active = plan.activeHabits
        let fallback = String(localized: "plan.headline.default", defaultValue: "Today from your plan")
        if active.isEmpty { return fallback }
        var counts: [String: Int] = [:]
        for h in active { if let p = h.pillar, headlinePillarOrder.contains(p) { counts[p, default: 0] += 1 } }
        var best: String?
        for p in headlinePillarOrder {
            let n = counts[p] ?? 0
            if n > 0, best == nil || n > (counts[best!] ?? 0) { best = p }
        }
        if let best, let line = pillarHeadline(best) { return line }
        return active.allSatisfy(\.isSelfInitiated)
            ? String(localized: "plan.headline.selfOnly", defaultValue: "The habits you chose")
            : fallback
    }

    /// The line under the headline: the current moment's count when it has habits, the day's count otherwise,
    /// and "all done" when nothing is left.
    static func subtitle(_ actions: [HabitAction], hour: Int) -> String {
        let done = actions.filter(\.done).count
        if actions.count - done <= 0 { return String(localized: "plan.allDone", defaultValue: "All done for today ✓") }
        let now = HabitSlot.current(hour: hour)
        let inNow = actions.filter { $0.slot == now }
        if !inNow.isEmpty {
            let nowDone = inNow.filter(\.done).count
            return String(localized: "plan.progress.moment", defaultValue: "\(now.label) · \(nowDone) of \(inNow.count) done")
        }
        return String(localized: "plan.progress.day", defaultValue: "\(done) of \(actions.count) done")
    }
}
