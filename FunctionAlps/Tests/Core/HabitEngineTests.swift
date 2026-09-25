import Foundation
import Testing
@testable import FunctionAlps

// 2026-09-25 is a Friday; 2026-09-21 Monday, -22 Tuesday, -24 Thursday, -26 Saturday.
@Suite("HabitEngine — the Habit Loop's arithmetic (port of the Expo lib/plan pure modules)")
struct HabitEngineTests {
    private let today = "2026-09-25"

    private func habit(_ id: String, title: String = "Habit", rule: String? = "FREQ=DAILY", status: String = "active",
                       source: String = "prescribed", pillar: String? = nil, slot: String? = nil, after: String? = nil,
                       created: String = "2026-09-01T08:00:00+00:00") -> HabitRow {
        HabitRow(id: id, carePlanItemId: source == "prescribed" ? "item-\(id)" : nil, title: title, description: nil,
                 frequencyRule: rule, status: status, source: source, pillar: pillar, slot: slot, appearsAfterHabitId: after,
                 easyTitle: nil, easyDescription: nil, revTitle: nil, revDescription: nil, createdAt: created)
    }

    private func done(_ habit: String, _ day: String) -> HabitCompletionRow {
        HabitCompletionRow(id: "c-\(habit)-\(day)", habitId: habit, completionDate: day)
    }

    private func plan(_ habits: [HabitRow], completions: [HabitCompletionRow] = [], header: HabitPlanHeader? = nil,
                      phases: [HabitPlanPhase] = []) -> HabitPlan {
        HabitPlan(day: today, header: header, phases: phases, habits: habits, completions: completions)
    }

    // MARK: Day math

    @Test func dayMathIsCalendarArithmeticOnKeys() {
        #expect(HabitEngine.shift("2026-09-25", by: -69) == "2026-07-18")
        #expect(HabitEngine.shift("2026-08-31", by: 1) == "2026-09-01")
        #expect(HabitEngine.shift("2026-03-01", by: -1) == "2026-02-28")
        #expect(HabitEngine.daysBetween("2026-09-01", "2026-09-25") == 24)
        #expect(HabitEngine.daysBetween("2026-09-25", "2026-09-01") == -24)
        #expect(HabitEngine.weekday("2026-09-25") == 5)   // Friday
        #expect(HabitEngine.weekday("2026-09-27") == 0)   // Sunday
        #expect(HabitEngine.shift("not-a-day", by: 3) == "not-a-day")
        #expect(HabitEngine.daysBetween("x", today) == nil)
    }

    // MARK: RRULE

    @Test func rulesParseLikeTheClinicalPipelineWritesThem() {
        #expect(HabitEngine.parseRule("FREQ=DAILY") == .init(freq: .daily, interval: 1, byday: []))
        #expect(HabitEngine.parseRule("RRULE:FREQ=DAILY") == .init(freq: .daily, interval: 1, byday: []))
        #expect(HabitEngine.parseRule("FREQ=DAILY;INTERVAL=2") == .init(freq: .daily, interval: 2, byday: []))
        #expect(HabitEngine.parseRule("FREQ=WEEKLY;BYDAY=TU,TH,SA") == .init(freq: .weekly, interval: 1, byday: [2, 4, 6]))
        #expect(HabitEngine.parseRule("freq=weekly; byday=mo") == .init(freq: .weekly, interval: 1, byday: [1]))
        #expect(HabitEngine.parseRule(nil).freq == .unknown)
        #expect(HabitEngine.parseRule("FREQ=MONTHLY").freq == .unknown)
        #expect(HabitEngine.parseRule("FREQ=DAILY;INTERVAL=0").interval == 1)   // nonsense interval → 1
    }

    @Test func dueDaysFollowTheRuleAndNeverPrecedeTheStart() {
        #expect(HabitEngine.isDue("FREQ=DAILY", on: today, start: "2026-09-01"))
        #expect(!HabitEngine.isDue("FREQ=DAILY", on: "2026-08-31", start: "2026-09-01"))   // before the habit existed
        #expect(HabitEngine.isDue(nil, on: today, start: "2026-09-01"))                    // unknown = due every day
        #expect(HabitEngine.isDue("FREQ=MONTHLY", on: today, start: "2026-09-01"))         // unreadable = shown, never hidden
        // Every other day from the 1st: the 25th is 24 days on → due; the 24th is not.
        #expect(HabitEngine.isDue("FREQ=DAILY;INTERVAL=2", on: today, start: "2026-09-01"))
        #expect(!HabitEngine.isDue("FREQ=DAILY;INTERVAL=2", on: "2026-09-24", start: "2026-09-01"))
        // Tue/Thu/Sat: Friday is not.
        #expect(!HabitEngine.isDue("FREQ=WEEKLY;BYDAY=TU,TH,SA", on: today, start: "2026-09-01"))
        #expect(HabitEngine.isDue("FREQ=WEEKLY;BYDAY=TU,TH,SA", on: "2026-09-24", start: "2026-09-01"))
        // Weekly with no BYDAY: the start's weekday (a Tuesday start → Tuesdays).
        #expect(HabitEngine.isDue("FREQ=WEEKLY", on: "2026-09-22", start: "2026-09-01"))
        #expect(!HabitEngine.isDue("FREQ=WEEKLY", on: today, start: "2026-09-01"))
        // Every second week: the 22nd is week 3 (odd) from the 1st → not due; the 15th (week 2) is.
        #expect(!HabitEngine.isDue("FREQ=WEEKLY;INTERVAL=2", on: "2026-09-22", start: "2026-09-01"))
        #expect(HabitEngine.isDue("FREQ=WEEKLY;INTERVAL=2", on: "2026-09-15", start: "2026-09-01"))
    }

    // MARK: Streaks

    @Test func aStreakCountsDueDaysAndTodayPendingDoesNotBreakIt() {
        let h = habit("a", created: "2026-09-20T07:00:00+00:00")
        let four = ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24"].map { done("a", $0) }
        #expect(HabitEngine.currentStreak(h, completions: four, today: today) == 4)          // today not yet done: pending
        #expect(HabitEngine.currentStreak(h, completions: four + [done("a", today)], today: today) == 5)
        #expect(HabitEngine.currentStreak(h, completions: [done("a", "2026-09-22"), done("a", "2026-09-24")], today: today) == 1)  // the 23rd broke it
        #expect(HabitEngine.currentStreak(h, completions: [], today: today) == 0)
        // Another habit's completions never count.
        #expect(HabitEngine.currentStreak(h, completions: [done("b", "2026-09-24")], today: today) == 0)
        // The walk stops where the habit begins: created the 20th, the 19th is not a miss.
        let sinceCreation = ["2026-09-20", "2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24"].map { done("a", $0) }
        #expect(HabitEngine.currentStreak(h, completions: sinceCreation, today: today) == 5)
    }

    @Test func nonDueDaysNeverBreakAStreak() {
        // Tue/Thu/Sat, created the 1st; done every Tue/Thu/Sat from the 15th. Friday the 25th is not due.
        let h = habit("w", rule: "FREQ=WEEKLY;BYDAY=TU,TH,SA")
        let dues = ["2026-09-15", "2026-09-17", "2026-09-19", "2026-09-22", "2026-09-24"].map { done("w", $0) }
        #expect(HabitEngine.currentStreak(h, completions: dues, today: today) == 5)
        #expect(HabitEngine.currentStreak(h, completions: Array(dues.dropFirst(2)), today: today) == 3)   // 19 · 22 · 24 done; the 17th, a due day, was not
    }

    // MARK: Sequencing

    @Test func aHabitWaitsForItsPredecessorButBadDataNeverHidesOne() {
        let a = habit("a"), b = habit("b", after: "a"), c = habit("c", after: "b")
        let all = [a, b, c]
        #expect(HabitEngine.visibleToday(a, in: all, doneIds: []))
        #expect(!HabitEngine.visibleToday(b, in: all, doneIds: []))                 // waiting on a
        #expect(HabitEngine.visibleToday(b, in: all, doneIds: ["a"]))
        #expect(!HabitEngine.visibleToday(c, in: all, doneIds: ["a"]))              // waiting on b
        #expect(HabitEngine.visibleToday(c, in: all, doneIds: ["a", "b"]))
        // Dangling reference → visible.
        #expect(HabitEngine.visibleToday(habit("d", after: "ghost"), in: all, doneIds: []))
        // A cycle → visible (fail safe).
        let x = habit("x", after: "y"), y = habit("y", after: "x")
        #expect(HabitEngine.visibleToday(x, in: [x, y], doneIds: []))
        // Upstream dangling beyond the immediate predecessor: the predecessor is visible and completable — keep waiting.
        let p = habit("p", after: "ghost"), q = habit("q", after: "p")
        #expect(!HabitEngine.visibleToday(q, in: [p, q], doneIds: []))
    }

    // MARK: Today

    @Test func todayLeadsWithTheCurrentMomentAndKeepsDoneWorkVisible() {
        let habits = [
            habit("m-done", title: "Morning done", slot: "morning"),
            habit("m-undone", title: "Morning undone", slot: "morning"),
            habit("mid", title: "Midday", slot: "midday"),
            habit("eve", title: "Evening", slot: "evening"),
            habit("any", title: "Anytime"),
            habit("paused", title: "Paused", status: "paused"),
            habit("offday", title: "Off day", rule: "FREQ=WEEKLY;BYDAY=TU"),
            habit("chained", title: "Chained", slot: "midday", after: "mid"),
        ]
        let p = plan(habits, completions: [done("m-done", today)])
        let actions = HabitEngine.todayActions(p, hour: 12)   // midday
        #expect(actions.map(\.id) == ["mid", "any", "eve", "m-undone", "m-done"])
        #expect(actions.first { $0.id == "m-done" }?.done == true)
        #expect(actions.first { $0.id == "m-done" }?.completionId == "c-m-done-2026-09-25")
        #expect(actions.first { $0.id == "mid" }?.done == false)
        // In the evening the evening habit leads; the morning and midday ones become catch-up, undone first,
        // each group in the practice's (creation) order.
        #expect(HabitEngine.todayActions(p, hour: 19).map(\.id) == ["eve", "any", "m-undone", "mid", "m-done"])
        // Once the midday habit is done, the chained one appears behind it.
        let later = HabitPlan(day: today, header: nil, phases: [], habits: habits, completions: [done("m-done", today), done("mid", today)])
        #expect(HabitEngine.todayActions(later, hour: 12).map(\.id) == ["mid", "chained", "any", "eve", "m-undone", "m-done"])
    }

    @Test func facesFollowTheDaysBandAndKeepTheIdentity() {
        var sit = habit("sit", title: "Ten sit-to-stands", slot: "midday")
        sit = HabitRow(id: sit.id, carePlanItemId: sit.carePlanItemId, title: sit.title, description: "From a chair.", frequencyRule: sit.frequencyRule,
                       status: sit.status, source: sit.source, pillar: "exercise", slot: sit.slot, appearsAfterHabitId: nil,
                       easyTitle: "Five sit-to-stands", easyDescription: "Half a round still counts.", revTitle: "Two rounds of ten", revDescription: nil, createdAt: sit.createdAt)
        let plain = habit("veg", title: "Vegetables on half the plate")   // no gentler or further version written
        let p = plan([sit, plain], completions: [done("sit", today)])

        let low = HabitEngine.todayActions(p, hour: 12, band: .low)
        #expect(low.map(\.title) == ["Five sit-to-stands", "Vegetables on half the plate"])
        #expect(low[0].face == .easy && low[0].detail == "Half a round still counts.")
        #expect(low[1].face == .standard)                                        // nothing gentler was written → as it is
        #expect(low[0].id == "sit" && low[0].completionId == "c-sit-2026-09-25")  // the identity and today's check-off are the habit's

        let high = HabitEngine.todayActions(p, hour: 12, band: .high)
        #expect(high[0].title == "Two rounds of ten" && high[0].face == .progression)
        #expect(high[0].detail == "From a chair.")                               // no further description → the habit's own

        #expect(HabitEngine.todayActions(p, hour: 12, band: .mid)[0].face == .standard)
        #expect(HabitEngine.todayActions(p, hour: 12)[0].title == "Ten sit-to-stands")   // no band yet: as written
    }

    @Test func streaksRideOnTheActions() {
        let h = habit("a", created: "2026-09-20T07:00:00+00:00")
        let p = plan([h], completions: ["2026-09-23", "2026-09-24"].map { done("a", $0) })
        #expect(HabitEngine.todayActions(p, hour: 9).first?.streak == 2)
    }

    // MARK: The headline

    @Test func theHeadlineClimbsAFixedLadder() {
        let exercise = [habit("a", pillar: "exercise"), habit("b", pillar: "exercise"), habit("c", pillar: "sleep")]
        let generic = HabitPlanHeader(id: "cp", title: "Care plan — 2026-08-15", startDate: "2026-09-01", objectiveLine: nil)
        // 1. The clinician's objective line wins outright.
        #expect(HabitEngine.headline(plan(exercise, header: HabitPlanHeader(id: "cp", title: "T", startDate: nil, objectiveLine: " Getting towards more stamina "))) == "Getting towards more stamina")
        // 2. The current phase's title: day 24 → week 4 → the second phase.
        let phases = [HabitPlanPhase(phaseKey: "p1", weekStart: 1, weekEnd: 2, title: "Settle the rhythm", summary: nil),
                      HabitPlanPhase(phaseKey: "p2", weekStart: 3, weekEnd: nil, title: "Build on it", summary: nil)]
        #expect(HabitEngine.headline(plan(exercise, header: generic, phases: phases)) == "Build on it")
        // 3. A real plan title; a generic one is skipped.
        #expect(HabitEngine.headline(plan(exercise, header: HabitPlanHeader(id: "cp", title: "Autumn reset", startDate: nil, objectiveLine: nil))) == "Autumn reset")
        // 4. The dominant pillar of the active habits.
        #expect(HabitEngine.headline(plan(exercise, header: generic)) == HabitEngine.pillarHeadline("exercise"))
        // Ties break in the fixed order (sleep before nutrition), so the line never flickers.
        #expect(HabitEngine.headline(plan([habit("a", pillar: "nutrition"), habit("b", pillar: "sleep")])) == HabitEngine.pillarHeadline("sleep"))
        // 5. All the member's own, no pillar → "the habits you chose"; 6. nothing active → the default.
        #expect(HabitEngine.headline(plan([habit("s", source: "self_initiated")])) == String(localized: "plan.headline.selfOnly", defaultValue: "The habits you chose"))
        #expect(HabitEngine.headline(plan([habit("p", status: "paused", pillar: "exercise")])) == String(localized: "plan.headline.default", defaultValue: "Today from your plan"))
        #expect(HabitEngine.isGenericPlanTitle("Untitled plan"))
        #expect(HabitEngine.isGenericPlanTitle("2026-08-15"))
        #expect(!HabitEngine.isGenericPlanTitle("Careful eating"))   // "care plan" is a phrase, not a prefix match on "Careful"
    }

    @Test func planWeeksAndPhases() {
        #expect(HabitEngine.planWeek(start: "2026-09-01", today: today) == 4)
        #expect(HabitEngine.planWeek(start: today, today: today) == 1)
        #expect(HabitEngine.planWeek(start: "2026-10-01", today: today) == nil)   // not started
        #expect(HabitEngine.planWeek(start: nil, today: today) == nil)
        let open = HabitPlanPhase(phaseKey: "p", weekStart: 3, weekEnd: nil, title: "Open-ended", summary: nil)
        #expect(HabitEngine.currentPhase([open], start: "2026-09-01", today: today)?.phaseKey == "p")
        #expect(HabitEngine.currentPhase([open], start: "2026-09-20", today: today) == nil)   // week 1, phase starts week 3
    }

    // MARK: The subtitle

    @Test func theSubtitleCountsTheMomentWhenItHasHabitsElseTheDay() {
        let a = HabitAction(id: "1", title: "A", detail: nil, slot: .morning, completionId: "c", streak: 0)
        let b = HabitAction(id: "2", title: "B", detail: nil, slot: .morning, completionId: nil, streak: 0)
        let c = HabitAction(id: "3", title: "C", detail: nil, slot: nil, completionId: nil, streak: 0)
        #expect(HabitEngine.subtitle([a, b, c], hour: 8) == "Morning · 1 of 2 done")   // the current moment's count
        #expect(HabitEngine.subtitle([a, b, c], hour: 13) == "1 of 3 done")             // midday has none: the day's
        #expect(HabitEngine.subtitle([a], hour: 8) == "All done for today ✓")
        #expect(HabitSlot.current(hour: 10) == .morning)
        #expect(HabitSlot.current(hour: 11) == .midday)
        #expect(HabitSlot.current(hour: 17) == .evening)
    }
}
