import Foundation
import Testing
@testable import FunctionAlps

@Suite("My health plan — the page's arithmetic")
struct PlanPageTests {
    // 2026-10-01 is a Thursday.
    private let today = "2026-10-01"

    private func habit(_ id: String, rule: String = "FREQ=DAILY", slot: String? = nil, status: String = "active",
                       card: String? = nil, created: String = "2026-09-01T08:00:00+00:00") -> HabitRow {
        HabitRow(id: id, carePlanItemId: "i-\(id)", title: "Habit \(id)", description: nil, frequencyRule: rule, status: status,
                 source: "prescribed", pillar: nil, slot: slot, appearsAfterHabitId: nil, easyTitle: nil, easyDescription: nil,
                 revTitle: nil, revDescription: nil, createdAt: created, habitBankId: card)
    }

    private func done(_ habit: String, _ day: String) -> HabitCompletionRow {
        HabitCompletionRow(id: "c-\(habit)-\(day)", habitId: habit, completionDate: day)
    }

    private func plan(_ habits: [HabitRow], _ completions: [HabitCompletionRow] = [], phases: [HabitPlanPhase] = [],
                      cards: [String: ActionCardRow] = [:]) -> HabitPlan {
        var p = HabitPlan(day: today, header: nil, phases: phases, habits: habits, completions: completions)
        p.cards = cards
        return p
    }

    @Test func theWeekRunsMondayToSunday() {
        #expect(PlanPageLogic.weekDays(today: today) == ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
        #expect(PlanPageLogic.weekDays(today: "2026-10-04").first == "2026-09-28")
        #expect(PlanPageLogic.weekDays(today: "2026-09-28").first == "2026-09-28")
    }

    @Test func eachDaySaysHowMuchOfWhatWasDueGotDone() {
        // Two daily habits; Monday both done, Tuesday one, Wednesday none, Thursday (today) both.
        let p = plan([habit("a"), habit("b")], [
            done("a", "2026-09-28"), done("b", "2026-09-28"),
            done("a", "2026-09-29"),
            done("a", "2026-10-01"), done("b", "2026-10-01"),
        ])
        let week = PlanPageLogic.week(p)
        #expect(week.map(\.state) == [.full, .partial, .none, .full, .upcoming, .upcoming, .upcoming])
        let totals = PlanPageLogic.weekTotals(week)
        #expect(totals.done == 5 && totals.due == 8)
    }

    @Test func aWeeklyHabitsOffDayIsARestNotAMiss() {
        let p = plan([habit("w", rule: "FREQ=WEEKLY;BYDAY=MO")], [done("w", "2026-09-28")])
        let week = PlanPageLogic.week(p)
        #expect(week[0].state == .full)
        #expect(week[1].state == .rest)
        #expect(PlanPageLogic.weekTotals(week).due == 1)
    }

    @Test func pausedHabitsAndOnesCreatedLaterAreNotCounted() {
        let p = plan([habit("p", status: "paused"), habit("n", created: "2026-09-30T08:00:00+00:00")])
        let week = PlanPageLogic.week(p)
        #expect(week[0].state == .rest)
        #expect(week[2].state == .none && week[2].due == 1)
    }

    @Test func phasesAreDoneCurrentOrComingUp() {
        let settle = HabitPlanPhase(phaseKey: "p1", weekStart: 1, weekEnd: 2, title: "Settle", summary: nil)
        let rebuild = HabitPlanPhase(phaseKey: "p2", weekStart: 3, weekEnd: 6, title: "Rebuild", summary: nil)
        let open = HabitPlanPhase(phaseKey: "p3", weekStart: 7, weekEnd: nil, title: "Consolidate", summary: nil)
        #expect(PlanPageLogic.phaseState(settle, week: 5) == .done)
        #expect(PlanPageLogic.phaseState(rebuild, week: 5) == .current)
        #expect(PlanPageLogic.phaseState(open, week: 5) == .upcoming)
        #expect(PlanPageLogic.phaseState(open, week: 30) == .current)
        #expect(PlanPageLogic.phaseState(settle, week: nil) == .upcoming)
        #expect(PlanPageLogic.totalWeeks([settle, rebuild, open]) == 6)
        #expect(PlanPageLogic.totalWeeks([open]) == nil)
    }

    @Test func readingListsEachLinkedArticleOnce_fromActiveActionsOnly() {
        var a = ActionCardRow(id: "b-1", title: "A")
        a.resources = [.init(kind: "article", slug: "sleep-basics", title: "Sleep basics")]
        var b = ActionCardRow(id: "b-2", title: "B")
        b.resources = [.init(kind: "article", slug: "sleep-basics", title: "Sleep basics"), .init(kind: "article", slug: "gut-101", title: "Gut 101")]
        var c = ActionCardRow(id: "b-3", title: "C")
        c.resources = [.init(kind: "article", slug: "paused-only")]
        let p = plan([habit("x", card: "b-1"), habit("y", card: "b-2"), habit("z", status: "paused", card: "b-3"), habit("n")],
                     cards: ["b-1": a, "b-2": b, "b-3": c])
        #expect(PlanPageLogic.articles(p).map(\.slug) == ["sleep-basics", "gut-101"])
    }

    @Test func actionsAreGroupedByMoment_anytimeLast() {
        let p = plan([habit("e", slot: "evening"), habit("any"), habit("m", slot: "morning"), habit("m2", slot: "morning")])
        let groups = PlanPageLogic.actionsByMoment(p)
        #expect(groups.map(\.slot) == [.morning, .evening, nil])
        #expect(groups[0].habits.map(\.id) == ["m", "m2"])
    }
}
