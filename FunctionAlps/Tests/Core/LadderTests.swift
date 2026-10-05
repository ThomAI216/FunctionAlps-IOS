import Foundation
import Testing
@testable import FunctionAlps

// 2026-10-06 is a Tuesday.
@Suite("Routines and ladders — Home's one routine, the caps, and the way up a ladder")
struct LadderTests {
    private let today = "2026-10-06"

    private func habit(_ id: String, slot: String? = nil, card: String? = nil, source: String = "prescribed",
                       created: String = "2026-09-01T08:00:00+00:00", levelSince: String? = nil, locked: Bool? = nil) -> HabitRow {
        var h = HabitRow(id: id, carePlanItemId: source == "prescribed" ? "item-\(id)" : nil, title: "Habit \(id)", description: nil,
                         frequencyRule: "FREQ=DAILY", status: "active", source: source, pillar: nil, slot: slot, appearsAfterHabitId: nil,
                         easyTitle: nil, easyDescription: nil, revTitle: nil, revDescription: nil, createdAt: created, habitBankId: card)
        h.levelSince = levelSince
        h.levelLocked = locked
        return h
    }

    private func card(_ id: String, next: String? = nil) -> ActionCardRow {
        var c = ActionCardRow(id: id, title: "Card \(id)")
        c.nextLevelId = next
        return c
    }

    private func done(_ habit: String, daysAgo: Int) -> HabitCompletionRow {
        let day = HabitEngine.shift(today, by: -daysAgo)
        return HabitCompletionRow(id: "c-\(habit)-\(day)", habitId: habit, completionDate: day)
    }

    private func plan(_ habits: [HabitRow], _ completions: [HabitCompletionRow] = []) -> HabitPlan {
        HabitPlan(day: today, header: nil, phases: [], habits: habits, completions: completions)
    }

    // MARK: Home shows one routine

    @Test func homeShowsOnlyTheRoutineOfTheMoment() {
        let p = plan([habit("m1", slot: "morning"), habit("m2", slot: "morning"), habit("d1", slot: "midday"),
                      habit("any"), habit("e1", slot: "evening")])
        #expect(HabitEngine.routineNow(p, hour: 7).actions.map(\.id) == ["m1", "m2"])
        #expect(HabitEngine.routineNow(p, hour: 7).slot == .morning)
        // Anytime actions belong to the day; the morning's and the evening's stay out.
        #expect(HabitEngine.routineNow(p, hour: 13).actions.map(\.id) == ["d1", "any"])
        #expect(HabitEngine.routineNow(p, hour: 20).actions.map(\.id) == ["e1"])
        // Even a done morning action does not follow the member into the evening.
        let doneMorning = plan(p.habits, [done("m1", daysAgo: 0)])
        #expect(HabitEngine.routineNow(doneMorning, hour: 20).actions.map(\.id) == ["e1"])
    }

    @Test func homeShowsUpToTheRoutinesCapAndCountsTheRest() {
        let mornings = (1...5).map { habit("m\($0)", slot: "morning") }
        let now = HabitEngine.routineNow(plan(mornings), hour: 8)
        #expect(now.actions.count == 3)
        #expect(now.more == 2)
        let days = (1...7).map { habit("d\($0)", slot: "midday") }
        #expect(HabitEngine.routineNow(plan(days), hour: 12).actions.count == 6)
    }

    @Test func theFlameLightsFromTheFirstDay() {
        #expect(HabitEngine.streakBadgeMin == 1)
        let p = plan([habit("m1", slot: "morning")], [done("m1", daysAgo: 1)])
        #expect(HabitEngine.routineNow(p, hour: 8).actions.first?.streak == 1)
    }

    // MARK: Caps on what a member adds

    @Test func routinesCapAtThreeSixThreeAndTwoForANewMember() {
        let veteran = habit("old", slot: "evening", created: "2026-08-01T08:00:00+00:00")
        let morning = (1...3).map { habit("m\($0)", slot: "morning") }
        let p = plan([veteran] + morning)
        #expect(!RoutineRules.isNewMember(p))
        #expect(RoutineRules.cap(.morning, plan: p) == 3)
        #expect(RoutineRules.cap(.midday, plan: p) == 6)
        #expect(!RoutineRules.canAdd(to: .morning, plan: p))
        #expect(RoutineRules.canAdd(to: .evening, plan: p))
        // A member whose first action is under two weeks old: two per routine.
        let fresh = plan([habit("n1", slot: "midday", created: "2026-10-01T08:00:00+00:00"),
                          habit("n2", created: "2026-10-02T08:00:00+00:00")])   // anytime counts with the day
        #expect(RoutineRules.isNewMember(fresh))
        #expect(RoutineRules.cap(.midday, plan: fresh) == 2)
        #expect(!RoutineRules.canAdd(to: .midday, plan: fresh))
        #expect(RoutineRules.canAdd(to: .morning, plan: fresh))
    }

    // MARK: Ladders

    @Test func aLadderIsWalkedBothWaysFromTheCard() {
        let cards = [card("a", next: "b"), card("b", next: "c"), card("c"), card("loner")]
        let ladder = LadderLogic.ladder(for: "b", in: cards)
        #expect(ladder?.levels.map(\.id) == ["a", "b", "c"])
        #expect(ladder?.index == 1)
        #expect(ladder?.number == 2)
        #expect(ladder?.count == 3)
        #expect(ladder?.next?.id == "c")
        #expect(LadderLogic.ladder(for: "loner", in: cards) == nil)       // on no ladder
        #expect(LadderLogic.ladder(for: "c", in: cards)?.isTop == true)
    }

    @Test func aNextLevelTheMemberCannotSeeYetIsComingSoon() {
        let cards = [card("a", next: "draft")]
        let ladder = LadderLogic.ladder(for: "a", in: cards)
        #expect(ladder?.hiddenNext == true)
        #expect(ladder?.count == 2)
        #expect(ladder?.next == nil)
        #expect(ladder?.isTop == false)
        let h = habit("h", card: "a")
        #expect(LadderLogic.state(h, ladder: ladder!, plan: plan([h])) == .comingSoon)
    }

    @Test func twoLaddersMeetingOnOneCardAlwaysShowTheSameLevelsBelow() {
        let cards = [card("walk-lunch", next: "brisk"), card("brisk", next: "run"), card("run"), card("a-stretch", next: "brisk")]
        let one = LadderLogic.ladder(for: "brisk", in: cards)
        let other = LadderLogic.ladder(for: "brisk", in: cards.reversed())
        #expect(one?.levels.map(\.id) == ["a-stretch", "brisk", "run"])
        #expect(other?.levels.map(\.id) == one?.levels.map(\.id))
    }

    @Test func aCycleInTheDataNeverLoops() {
        let cards = [card("a", next: "b"), card("b", next: "a")]
        let ladder = LadderLogic.ladder(for: "a", in: cards)
        #expect(ladder?.levels.count == 2)
    }

    @Test func threeTimesInSevenDaysAtThisLevelOpensTheNext() {
        let cards = [card("a", next: "b"), card("b")]
        let ladder = LadderLogic.ladder(for: "a", in: cards)!
        let h = habit("h", slot: "morning", card: "a")
        #expect(LadderLogic.state(h, ladder: ladder, plan: plan([h], [done("h", daysAgo: 0), done("h", daysAgo: 2)]))
                == .building(done: 2, needed: 3))
        #expect(LadderLogic.state(h, ladder: ladder, plan: plan([h], [done("h", daysAgo: 0), done("h", daysAgo: 2), done("h", daysAgo: 6)]))
                == .ready)
        // Older than the 7-day window: it does not count.
        #expect(LadderLogic.state(h, ladder: ladder, plan: plan([h], [done("h", daysAgo: 0), done("h", daysAgo: 2), done("h", daysAgo: 7)]))
                == .building(done: 2, needed: 3))
    }

    @Test func onlyCompletionsAtTheCurrentLevelCount() {
        let cards = [card("a", next: "b"), card("b", next: "c"), card("c")]
        let ladder = LadderLogic.ladder(for: "b", in: cards)!
        // Reached level b two days ago: the days before belong to level a.
        let h = habit("h", card: "b", levelSince: HabitEngine.shift(today, by: -2))
        let p = plan([h], [done("h", daysAgo: 0), done("h", daysAgo: 1), done("h", daysAgo: 3), done("h", daysAgo: 4)])
        #expect(LadderLogic.state(h, ladder: ladder, plan: p) == .building(done: 2, needed: 3))
    }

    @Test func oneChangePerRoutinePerWeekAndTheClinicianLock() {
        let cards = [card("a", next: "b"), card("b")]
        let ladder = LadderLogic.ladder(for: "a", in: cards)!
        let h = habit("h", slot: "evening", card: "a")
        let movedYesterday = habit("o", slot: "evening", levelSince: HabitEngine.shift(today, by: -1))
        let threeDays = [done("h", daysAgo: 0), done("h", daysAgo: 1), done("h", daysAgo: 2)]
        #expect(LadderLogic.state(h, ladder: ladder, plan: plan([h, movedYesterday], threeDays))
                == .waiting(from: HabitEngine.shift(today, by: 6)))
        // Another routine's change does not hold this one back.
        let otherRoutine = habit("o", slot: "morning", levelSince: HabitEngine.shift(today, by: -1))
        #expect(LadderLogic.state(h, ladder: ladder, plan: plan([h, otherRoutine], threeDays)) == .ready)
        // A level the clinician keeps.
        let locked = habit("h", slot: "evening", card: "a", locked: true)
        #expect(LadderLogic.state(locked, ladder: ladder, plan: plan([locked], threeDays)) == .locked)
    }
}
