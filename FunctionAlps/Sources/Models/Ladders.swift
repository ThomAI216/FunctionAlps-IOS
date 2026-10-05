import Foundation

// Evolution ladders and routine rules (owner, 2026-10-06; design `docs/action-cards/routines-design.md` §3–4).
//
// A card may point at its next level (`habit_bank.next_level_id`); a chain of cards is a ladder. A member's habit
// moves up IN PLACE through the `member_level_up` RPC, which is the authority: the rules below only let the screen
// say where the member stands and what comes next. Like the rest of the Habit Loop, they read completions only,
// never a health signal. Every date is an explicit `YYYY-MM-DD`; there is no clock in here.

/// One habit's ladder: the cards from the first level to the last the member may see.
struct ActionLadder: Sendable, Equatable {
    /// Levels in order, first to last visible.
    let levels: [ActionCardRow]
    /// The habit's current level in `levels`.
    let index: Int
    /// The last visible level points at a next level the member cannot see yet (a draft): "coming soon".
    let hiddenNext: Bool

    var current: ActionCardRow { levels[index] }
    var next: ActionCardRow? { index + 1 < levels.count ? levels[index + 1] : nil }
    /// Total levels, counting a next level not published yet.
    var count: Int { levels.count + (hiddenNext ? 1 : 0) }
    /// 1-based, for "Level 2 of 3".
    var number: Int { index + 1 }
    var isTop: Bool { next == nil && !hiddenNext }
}

/// Where a habit stands on its way to the next level.
enum LevelState: Sendable, Equatable {
    /// `done` of `needed` in the last 7 days at this level.
    case building(done: Int, needed: Int)
    /// The rule is met: the member may try the next level.
    case ready
    /// The rule is met but another action of the same routine moved up this week: open again on `from`.
    case waiting(from: String)
    /// The clinician keeps this level for now.
    case locked
    /// A next level exists but is not published yet.
    case comingSoon
    /// Top of the ladder.
    case top
}

enum LadderLogic {
    /// Completions needed at a level before the next one opens, inside `windowDays` (owner, 2026-10-06:
    /// "always do it two or three times first"). The RPC enforces the same numbers.
    static let completionsToLevelUp = 3
    static let windowDays = 7
    /// A ladder longer than this is bad data; the walk stops rather than loop.
    static let maxLevels = 12

    /// The ladder a card sits on, among the cards the member can see. Nil when the card is on no ladder (nothing
    /// points at it and it points at nothing) or is not visible.
    static func ladder(for cardId: String, in cards: [ActionCardRow]) -> ActionLadder? {
        let byId = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        guard let card = byId[cardId] else { return nil }
        let previous = Dictionary(cards.compactMap { c in c.nextLevelId.map { ($0, c) } }, uniquingKeysWith: { a, _ in a })

        var below: [ActionCardRow] = []
        var seen: Set<String> = [card.id]
        var cursor = card
        while let prev = previous[cursor.id], !seen.contains(prev.id), below.count < maxLevels {
            below.insert(prev, at: 0); seen.insert(prev.id); cursor = prev
        }
        var above: [ActionCardRow] = []
        var hiddenNext = false
        cursor = card
        while let nextId = cursor.nextLevelId, !seen.contains(nextId), above.count < maxLevels {
            guard let next = byId[nextId] else { hiddenNext = true; break }
            above.append(next); seen.insert(nextId); cursor = next
        }
        if below.isEmpty && above.isEmpty && !hiddenNext { return nil }
        return ActionLadder(levels: below + [card] + above, index: below.count, hiddenNext: hiddenNext)
    }

    /// The first day that counts at this level: the level's start, or the window's first day, whichever is later.
    static func windowStart(_ habit: HabitRow, today: String) -> String {
        let levelStart = habit.levelSince.map { String($0.prefix(10)) } ?? habit.createdDay
        let windowFirst = HabitEngine.shift(today, by: -(windowDays - 1))
        return max(levelStart, windowFirst)
    }

    /// Days done at the current level inside the window (one per day, however many check-offs).
    static func doneAtLevel(_ habit: HabitRow, completions: [HabitCompletionRow], today: String) -> Int {
        let from = windowStart(habit, today: today)
        return Set(completions.filter { $0.habitId == habit.id && $0.day >= from && $0.day <= today }.map(\.day)).count
    }

    /// One change per routine per week: if another active habit of the same routine moved up in the last 7 days,
    /// the day this one may move up.
    static func routineOpensOn(_ habit: HabitRow, in habits: [HabitRow], today: String) -> String? {
        let since = HabitEngine.shift(today, by: -windowDays)
        let recent = habits.filter { other in
            other.id != habit.id && other.isActive && other.slot == habit.slot
                && (other.levelSince.map { String($0.prefix(10)) } ?? "") > since
        }
        guard let latest = recent.compactMap({ $0.levelSince.map { String($0.prefix(10)) } }).max() else { return nil }
        return HabitEngine.shift(latest, by: windowDays)
    }

    static func state(_ habit: HabitRow, ladder: ActionLadder, plan: HabitPlan) -> LevelState {
        if ladder.next == nil { return ladder.hiddenNext ? .comingSoon : .top }
        if habit.levelLocked == true { return .locked }
        let done = doneAtLevel(habit, completions: plan.completions, today: plan.day)
        guard done >= completionsToLevelUp else { return .building(done: done, needed: completionsToLevelUp) }
        if let from = routineOpensOn(habit, in: plan.habits, today: plan.day) { return .waiting(from: from) }
        return .ready
    }
}

/// The caps that keep a day doable (owner, 2026-10-06): three in the morning, six over the day, three in the
/// evening; a new member starts at two in each.
enum RoutineRules {
    /// How long a member counts as new, from their first action.
    static let newMemberDays = 14
    static let newMemberCap = 2

    /// The routine a habit belongs to: anytime actions count with the day.
    static func routine(of habit: HabitRow) -> HabitSlot { habit.slotValue ?? .midday }

    /// New while the member's first action is less than two weeks old.
    static func isNewMember(_ plan: HabitPlan) -> Bool {
        guard let first = plan.habits.map(\.createdDay).min(),
              let days = HabitEngine.daysBetween(first, plan.day) else { return true }
        return days < newMemberDays
    }

    static func cap(_ slot: HabitSlot, plan: HabitPlan) -> Int {
        isNewMember(plan) ? min(newMemberCap, slot.cap) : slot.cap
    }

    /// Active actions already in a routine.
    static func count(_ slot: HabitSlot, plan: HabitPlan) -> Int {
        plan.activeHabits.filter { routine(of: $0) == slot }.count
    }

    /// May the member add one more action to this routine themselves?
    static func canAdd(to slot: HabitSlot, plan: HabitPlan) -> Bool {
        count(slot, plan: plan) < cap(slot, plan: plan)
    }
}
