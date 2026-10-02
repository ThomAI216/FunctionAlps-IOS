import Foundation

// "My health plan" — the page behind the Home card (owner, 2026-10-02, after the approved mockup): the objective
// and goals, the journey through the phases, this week's priorities, the member's actions with their week, the
// plan in detail, and what to read. Pure arithmetic over `HabitPlan`; no clock, no I/O, nothing computed from a
// health signal (rule 9) — the same counting the Home card does, laid out over a week.

enum PlanPageLogic {
    /// One day of the week strip: how much of what was due got done.
    enum DayState: Equatable, Sendable {
        /// Everything due was done.
        case full
        /// Some of it.
        case partial
        /// Due, none done.
        case none
        /// Nothing was due (a weekly habit's off day, or no habits yet).
        case rest
        /// Still ahead this week.
        case upcoming
    }

    struct WeekDay: Equatable, Sendable, Identifiable {
        let day: String
        let state: DayState
        let due: Int
        let done: Int
        var id: String { day }
    }

    /// The Monday-to-Sunday week `today` falls in.
    static func weekDays(today: String) -> [String] {
        guard let dow = HabitEngine.weekday(today) else { return [today] }
        let sinceMonday = (dow + 6) % 7
        let monday = HabitEngine.shift(today, by: -sinceMonday)
        return (0..<7).map { HabitEngine.shift(monday, by: $0) }
    }

    /// The week strip: per day, the active habits due that day and how many of them were done.
    static func week(_ plan: HabitPlan) -> [WeekDay] {
        weekDays(today: plan.day).map { day in
            if let ahead = HabitEngine.daysBetween(plan.day, day), ahead > 0 {
                return WeekDay(day: day, state: .upcoming, due: 0, done: 0)
            }
            let due = plan.activeHabits.filter { HabitEngine.isDue($0.frequencyRule, on: day, start: $0.createdDay) }
            let doneIds = HabitEngine.doneIds(plan.completions, on: day)
            let done = due.filter { doneIds.contains($0.id) }.count
            let state: DayState = due.isEmpty ? .rest : done == due.count ? .full : done > 0 ? .partial : .none
            return WeekDay(day: day, state: state, due: due.count, done: done)
        }
    }

    /// "18 of 24" so far this week (today included, the days ahead not).
    static func weekTotals(_ days: [WeekDay]) -> (done: Int, due: Int) {
        days.reduce((0, 0)) { ($0.0 + $1.done, $0.1 + $1.due) }
    }

    enum PhaseState: Equatable, Sendable { case done, current, upcoming }

    /// Where a phase stands for the member's week; nil week (no start date) = every phase upcoming.
    static func phaseState(_ phase: HabitPlanPhase, week: Int?) -> PhaseState {
        guard let week else { return .upcoming }
        if week < phase.weekStart { return .upcoming }
        if let end = phase.weekEnd, week > end { return .done }
        return .current
    }

    /// The plan's length in weeks — the last phase's end, when the clinician wrote one.
    static func totalWeeks(_ phases: [HabitPlanPhase]) -> Int? {
        phases.compactMap(\.weekEnd).max()
    }

    /// The library articles the member's active actions point at, once each, in the order the habits come.
    static func articles(_ plan: HabitPlan) -> [(slug: String, title: String?)] {
        var seen = Set<String>(), out: [(slug: String, title: String?)] = []
        for habit in plan.activeHabits {
            guard let card = habit.habitBankId.flatMap({ plan.cards[$0] }) else { continue }
            for link in ActionCardLogic.links(card.resources) {
                if case .article(let slug, let title) = link, seen.insert(slug).inserted { out.append((slug, title)) }
            }
        }
        return out
    }

    /// The member's active actions by moment (Morning · Midday · Evening · Anytime), creation order inside each.
    static func actionsByMoment(_ plan: HabitPlan) -> [(slot: HabitSlot?, habits: [HabitRow])] {
        let active = plan.activeHabits
        var out: [(slot: HabitSlot?, habits: [HabitRow])] = HabitSlot.order.compactMap { slot in
            let habits = active.filter { $0.slotValue == slot }
            return habits.isEmpty ? nil : (slot, habits)
        }
        let anytime = active.filter { $0.slotValue == nil }
        if !anytime.isEmpty { out.append((nil, anytime)) }
        return out
    }
}
