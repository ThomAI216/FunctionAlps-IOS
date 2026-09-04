import Foundation
import Testing
@testable import FunctionAlps

@Suite("Notification planner — what the phone schedules from today's state")
struct NotificationPlannerTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    // Wednesday 2 Sep 2026, 09:00.
    private var now: Date { date("2026-09-02 09:00") }

    private func ids(_ plan: [NotificationPlanner.Planned]) -> [String] { plan.map(\.id) }

    @Test("The three check-ins are planned every day for a week; a done moment drops today's only")
    func checkins() {
        var state = NotificationPlanner.State(now: now)
        state.momentsDone = [.morning]
        let plan = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        let morning = plan.filter { $0.kind == .morningCheckin }
        #expect(morning.count == 6)                                   // 7 days minus today
        #expect(!ids(plan).contains("checkin.morning.2026-09-02"))
        #expect(ids(plan).contains("checkin.morning.2026-09-03"))
        #expect(plan.filter { $0.kind == .middayCheckin }.count == 7)
        #expect(plan.first { $0.id == "checkin.midday.2026-09-02" }?.fireAt == date("2026-09-02 14:30"))
        #expect(plan.first { $0.id == "checkin.evening.2026-09-02" }?.route == "functionalps://checkin/evening")
    }

    @Test("Past times today are never scheduled")
    func pastTimes() {
        let state = NotificationPlanner.State(now: date("2026-09-02 15:00"))
        let plan = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        #expect(!ids(plan).contains("checkin.morning.2026-09-02"))
        #expect(!ids(plan).contains("checkin.midday.2026-09-02"))
        #expect(!ids(plan).contains("meal.lunch.2026-09-02"))
        #expect(ids(plan).contains("meal.dinner.2026-09-02"))
    }

    @Test("A meal logged in the lunch window silences the lunch reminder, not dinner's")
    func mealWindows() {
        var state = NotificationPlanner.State(now: now)
        state.mealsToday = [date("2026-09-02 12:10")]
        let plan = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        #expect(!ids(plan).contains("meal.lunch.2026-09-02"))
        #expect(plan.first { $0.id == "meal.dinner.2026-09-02" }?.fireAt == date("2026-09-02 20:15"))
        #expect(ids(plan).contains("meal.lunch.2026-09-03"))
    }

    @Test("2.5 h after an unrated meal — rated meals are simply absent from the state")
    func reaction() {
        var state = NotificationPlanner.State(now: date("2026-09-02 12:40"))
        state.unratedRecentMeals = [(id: "m1", loggedAt: date("2026-09-02 12:30")), (id: "old", loggedAt: date("2026-09-02 09:00"))]
        let plan = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        let r = plan.filter { $0.kind == .mealReaction }
        #expect(r.count == 1)                                          // 09:00 + 2.5 h is in the past
        #expect(r.first?.id == "meal.reaction.m1")
        #expect(r.first?.fireAt == date("2026-09-02 15:00"))
        #expect(r.first?.route == "functionalps://meal/m1?rate=1")
    }

    @Test("Weekly summary lands on Sunday 18:00 only; Apple Health stale 3 days after the last sync")
    func weeklyAndStale() {
        var state = NotificationPlanner.State(now: now)
        state.appleHealthConnected = true
        state.appleHealthLastSync = date("2026-09-01 07:00")
        let plan = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        let weekly = plan.filter { $0.kind == .weeklySummary }
        #expect(weekly.count == 1)
        #expect(weekly.first?.fireAt == date("2026-09-06 18:00"))
        #expect(plan.first { $0.kind == .wearableStale }?.fireAt == date("2026-09-04 07:00"))
    }

    @Test("Preferences switch each family off")
    func prefsOff() {
        var prefs = NotificationPrefs.default
        prefs.morningEnabled = false; prefs.middayEnabled = false; prefs.eveningEnabled = false
        prefs.mealRemindersEnabled = false; prefs.weeklySummaryEnabled = false; prefs.postMealFollowupEnabled = false
        var state = NotificationPlanner.State(now: now)
        state.unratedRecentMeals = [(id: "m1", loggedAt: now)]
        #expect(NotificationPlanner.plan(prefs: prefs, state: state, calendar: calendar).isEmpty)
    }

    @Test("Quiet hours move a reminder to the end of the window — across midnight too")
    func quietHours() {
        var prefs = NotificationPrefs.default
        prefs.quietStart = "22:00"; prefs.quietEnd = "07:30"
        let late = NotificationPlanner.Planned(id: "x", kind: .mealReaction, fireAt: date("2026-09-02 22:30"), title: "", body: "", route: "", threadId: "")
        let early = NotificationPlanner.Planned(id: "y", kind: .mealReaction, fireAt: date("2026-09-03 06:00"), title: "", body: "", route: "", threadId: "")
        let day = NotificationPlanner.Planned(id: "z", kind: .mealReaction, fireAt: date("2026-09-02 15:00"), title: "", body: "", route: "", threadId: "")
        let moved = NotificationPlanner.respectingQuietHours([late, early, day], prefs: prefs, calendar: calendar)
        #expect(moved[0].fireAt == date("2026-09-03 07:30"))
        #expect(moved[1].fireAt == date("2026-09-03 07:30"))
        #expect(moved[2].fireAt == date("2026-09-02 15:00"))
        prefs.quietHoursEnabled = false
        #expect(NotificationPlanner.respectingQuietHours([late], prefs: prefs, calendar: calendar)[0].fireAt == late.fireAt)
    }

    @Test("Prefs row → prefs and back keeps HH:mm; junk falls back")
    func prefsRow() {
        var row = NotificationPrefsRow()
        row.morningCheckinTime = "07:15:00"; row.quietHoursStart = "nonsense"; row.middayCheckinEnabled = false
        let p = row.prefs
        #expect(p.morningTime == "07:15")
        #expect(p.quietStart == "22:00")
        #expect(p.middayEnabled == false)
        let back = NotificationPrefsRow.write(p, patientId: "p1")
        #expect(back.morningCheckinTime == "07:15:00")
        #expect(back.apnsToken == nil)                                 // the token is never touched by a prefs save
    }

    @Test("Deep links: meal id parsing")
    func mealId() {
        #expect(AppRouter.mealId(from: URL(string: "functionalps://meal/abc?rate=1")!) == "abc")
        #expect(AppRouter.mealId(from: URL(string: "functionalps://checkin/morning")!) == nil)
    }

    @Test("Reaction flags follow the Food-tab vocabulary")
    func flags() {
        #expect(MealReactionSheet.flags(overall: 2, bloating: 6, fullness: 0, gas: 9) == ["overall_rough", "bloating", "gas"])
        #expect(MealReactionSheet.flags(overall: 5, bloating: 3, fullness: 6, gas: 0) == ["overall_off", "heavy"])
        #expect(MealReactionSheet.flags(overall: 9, bloating: 0, fullness: 0, gas: 0).isEmpty)
    }
}
