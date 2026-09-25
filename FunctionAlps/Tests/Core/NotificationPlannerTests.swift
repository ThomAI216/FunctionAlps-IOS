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

    @Test("Two check-ins a day for a week; a done moment drops today's only; midday is never planned")
    func checkins() {
        var state = NotificationPlanner.State(now: now)
        state.momentsDone = [.morning]
        let plan = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        let morning = plan.filter { $0.kind == .morningCheckin }
        #expect(morning.count == 6)                                   // 7 days minus today
        #expect(!ids(plan).contains("checkin.morning.2026-09-02"))
        #expect(ids(plan).contains("checkin.morning.2026-09-03"))
        #expect(plan.filter { $0.kind == .eveningCheckin }.count == 7)
        #expect(plan.first { $0.id == "checkin.evening.2026-09-02" }?.fireAt == date("2026-09-02 20:45"))
        #expect(plan.first { $0.id == "checkin.evening.2026-09-02" }?.route == "functionalps://checkin/evening")
        // The retired moment: not planned even for a member whose stored preference still has it on.
        var revived = NotificationPrefs.default
        revived.middayEnabled = true
        #expect(NotificationPlanner.plan(prefs: revived, state: state, calendar: calendar).allSatisfy { $0.kind != .middayCheckin })
    }

    @Test("Past times today are never scheduled")
    func pastTimes() {
        let state = NotificationPlanner.State(now: date("2026-09-02 15:00"))
        let plan = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        #expect(!ids(plan).contains("checkin.morning.2026-09-02"))
        #expect(ids(plan).contains("checkin.evening.2026-09-02"))    // 20:45 is still ahead at 15:00
        #expect(!ids(plan).contains("meal.lunch.2026-09-02"))
        #expect(ids(plan).contains("meal.dinner.2026-09-02"))
    }

    @Test("A meal logged at lunchtime silences today's lunch reminder, not dinner's")
    func mealWindows() {
        var state = NotificationPlanner.State(now: date("2026-09-02 11:00"))
        state.mealsToday = [.init(at: date("2026-09-02 10:50"), type: nil)]       // untyped: placed by the clock → breakfast
        #expect(ids(NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)).contains("meal.lunch.2026-09-02"))
        state.now = date("2026-09-02 11:45")
        state.mealsToday = [.init(at: date("2026-09-02 11:40"), type: .lunch)]    // an early lunch, before its 12:00 reminder
        let plan = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        #expect(!ids(plan).contains("meal.lunch.2026-09-02"))
        #expect(plan.first { $0.id == "meal.dinner.2026-09-02" }?.fireAt == date("2026-09-02 20:00"))
        #expect(ids(plan).contains("meal.lunch.2026-09-03"))
    }

    @Test("Meal slots come from the member's schedule: off days stay silent, a Sunday-only breakfast rings once")
    func scheduleSlots() {
        var schedule = MealSchedule.defaults
        schedule.set(.breakfast, weekdays: [1, 2, 3, 4, 5, 6], enabled: false)
        schedule.set(.breakfast, weekdays: [7], remindAt: "09:45")
        schedule.set(.afternoonSnack, weekdays: Array(1...7), enabled: true)
        let friday = NotificationPlanner.State(now: date("2026-09-04 07:00"))
        let plan = NotificationPlanner.plan(prefs: .default, schedule: schedule, state: friday, calendar: calendar)
        let breakfasts = plan.filter { $0.kind == .breakfast }
        #expect(breakfasts.map(\.id) == ["meal.breakfast.2026-09-06"])
        #expect(breakfasts.first?.fireAt == date("2026-09-06 09:45"))
        #expect(plan.first { $0.id == "meal.afternoon_snack.2026-09-04" }?.fireAt == date("2026-09-04 16:00"))
        #expect(plan.filter { $0.kind == .morningSnack }.isEmpty)
        #expect(plan.first { $0.kind == .lunch }?.route == "functionalps://food")
    }

    @Test("Meal slots are planned four days ahead; an unknown schedule plans none")
    func mealHorizon() {
        let state = NotificationPlanner.State(now: now)                            // Wednesday 09:00
        let plan = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        #expect(plan.filter { $0.kind == .lunch }.map(\.id) == ["meal.lunch.2026-09-02", "meal.lunch.2026-09-03", "meal.lunch.2026-09-04", "meal.lunch.2026-09-05"])
        #expect(plan.filter { $0.kind == .breakfast }.count == 3)                  // today's 08:00 is past
        #expect(plan.filter { $0.kind == .eveningCheckin }.count == 7)             // check-ins keep their week
        #expect(NotificationPlanner.plan(prefs: .default, schedule: nil, state: state, calendar: calendar).allSatisfy { !$0.kind.isMealSlot })
    }

    @Test("A snack does not count as lunch; the old fixed nudges keep their ids so pending ones reconcile")
    func snackIsNotLunch() {
        var schedule = MealSchedule.defaults
        schedule.set(.morningSnack, weekdays: Array(1...7), enabled: true)
        var state = NotificationPlanner.State(now: date("2026-09-02 10:30"))
        state.mealsToday = [.init(at: date("2026-09-02 10:20"), type: .snack)]
        #expect(ids(NotificationPlanner.plan(prefs: .default, schedule: schedule, state: state, calendar: calendar)).contains("meal.lunch.2026-09-02"))
        #expect(NotificationPlanner.Kind.lunch.rawValue == "meal.lunch" && NotificationPlanner.Kind.dinner.rawValue == "meal.dinner")
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

    @Test("Quiet hours drop a meal reminder instead of moving it to the next morning")
    func quietHoursDropMeals() {
        let prefs = NotificationPrefs.default                                      // quiet 22:00–07:30
        let dinner = NotificationPlanner.Planned(id: "meal.dinner.2026-09-02", kind: .dinner, fireAt: date("2026-09-02 22:15"), title: "", body: "", route: "", threadId: "")
        let reaction = NotificationPlanner.Planned(id: "r", kind: .mealReaction, fireAt: date("2026-09-02 22:30"), title: "", body: "", route: "", threadId: "")
        let kept = NotificationPlanner.respectingQuietHours([dinner, reaction], prefs: prefs, calendar: calendar)
        #expect(kept.map(\.id) == ["r"])
        #expect(kept.first?.fireAt == date("2026-09-03 07:30"))
    }

    @Test("No two reminders within 20 minutes: the check-in keeps its time, the rest step aside or drop")
    func spacing() {
        func p(_ id: String, _ kind: NotificationPlanner.Kind, _ at: String) -> NotificationPlanner.Planned {
            .init(id: id, kind: kind, fireAt: date(at), title: "", body: "", route: "", threadId: "")
        }
        let spaced = NotificationPlanner.spaced([
            p("meal.breakfast.x", .breakfast, "2026-09-02 08:00"),
            p("checkin.morning.x", .morningCheckin, "2026-09-02 08:00"),
            p("meal.morning_snack.x", .morningSnack, "2026-09-02 08:00"),
            p("meal.reaction.m", .mealReaction, "2026-09-02 08:00"),
            p("meal.lunch.x", .lunch, "2026-09-02 12:00"),
        ])
        #expect(spaced.map(\.id) == ["checkin.morning.x", "meal.breakfast.x", "meal.morning_snack.x", "meal.lunch.x"])
        #expect(spaced.map(\.fireAt) == [date("2026-09-02 08:00"), date("2026-09-02 08:20"), date("2026-09-02 08:40"), date("2026-09-02 12:00")])
    }

    @Test("The phone never holds more than 60 of ours — the nearest win")
    func pendingCap() {
        let start = date("2026-09-02 08:00")
        let many = (0..<80).map { i in
            NotificationPlanner.Planned(id: "x\(i)", kind: .weeklySummary, fireAt: start.addingTimeInterval(Double(i) * 3600), title: "", body: "", route: "", threadId: "")
        }
        let kept = NotificationPlanner.finalized(Array(many.reversed()), prefs: {
            var p = NotificationPrefs.default; p.quietHoursEnabled = false; return p
        }(), calendar: calendar)
        #expect(kept.count == 60)
        #expect(kept.first?.id == "x0" && kept.last?.id == "x59")
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

    @Test("A meal's three reads land on the columns the engines already read")
    func mealFeedback() {
        #expect(!MealFeedback().hasAnswer)

        // A rough one: digestion is the headline (overall), the pills set the symptom columns.
        var rough = MealFeedback(energy: .rough, focus: .off, digestion: .rough)
        rough.digestionPills = ["bloating", "gas", "overfull", "reflux"]
        rough.energyPills = ["energy_crash"]
        rough.focusPills = ["foggy"]
        #expect(rough.overall == 1)
        #expect(rough.bloating == 6 && rough.gasBurden == 6 && rough.fullness == 6 && rough.burning == 6)
        #expect(rough.fatigue == 6)
        #expect(rough.flags == ["overall_rough", "bloating", "gas", "heavy", "reflux", "energy_crash", "foggy"])
        #expect(rough.responses == ["digestion": 1, "overall": 1, "energy": 1, "focus": 3])

        // Middling digestion reads as "off"; a fine one carries no flag at all.
        #expect(MealFeedback(digestion: .okay).flags == ["overall_off"])
        #expect(MealFeedback(digestion: .good).flags.isEmpty)
        #expect(MealFeedback(digestion: .great).bloating == 0)

        // Only the bottom two steps ask what exactly went wrong.
        #expect(MealFeedback.Read.rough.isPoor && MealFeedback.Read.off.isPoor)
        #expect(!MealFeedback.Read.okay.isPoor && !MealFeedback.Read.good.isPoor && !MealFeedback.Read.great.isPoor)

        // A pill on its own is still an answer worth saving.
        var pillOnly = MealFeedback()
        pillOnly.digestionPills = ["nausea"]
        #expect(pillOnly.hasAnswer && pillOnly.overall == nil && pillOnly.flags == ["nausea"])
    }
}
