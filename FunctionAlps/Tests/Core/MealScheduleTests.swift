import Foundation
import Testing
@testable import FunctionAlps

@Suite("Meal schedule — the member's own meal times (member_meal_schedule)")
struct MealScheduleTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }()

    private func date(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    @Test("Always five slots on seven days; a partial read is filled from the defaults")
    func fullWeek() {
        #expect(MealSchedule.defaults.entries.count == 35)
        let partial = MealSchedule(entries: [MealScheduleEntry(slot: .dinner, weekday: 5, enabled: true, remindAt: "21:00", source: .member)])
        #expect(partial.entries.count == 35)
        #expect(partial.entry(.dinner, weekday: 5).remindAt == "21:00")
        #expect(partial.entry(.dinner, weekday: 4).remindAt == "20:00")
        #expect(partial.entry(.morningSnack, weekday: 1).enabled == false)
        #expect(partial.entry(.breakfast, weekday: 1).enabled == true)
    }

    @Test("ISO weekdays: Monday is 1, Sunday is 7")
    func isoWeekdays() {
        #expect(MealSchedule.isoWeekday(of: date("2026-09-07 12:00"), calendar: calendar) == 1)
        #expect(MealSchedule.isoWeekday(of: date("2026-09-05 12:00"), calendar: calendar) == 6)
        #expect(MealSchedule.isoWeekday(of: date("2026-09-06 12:00"), calendar: calendar) == 7)
    }

    @Test("The defaults reproduce the old fixed clock exactly, minute by minute")
    func defaultsAreTheOldClock() {
        for minute in stride(from: 0, to: 24 * 60, by: 5) {
            let at = calendar.date(byAdding: .minute, value: minute, to: date("2026-09-02 00:00"))!
            #expect(MealSchedule.defaults.mealType(at: at, calendar: calendar) == MealService.mealType(at: at, calendar: calendar), "at minute \(minute)")
        }
    }

    @Test("The member's word wins over the clock; a snack is the morning one before lunch")
    func typedMeals() {
        let s = MealSchedule.defaults
        #expect(s.slot(forMealAt: date("2026-09-02 18:30"), type: .lunch, calendar: calendar) == .lunch)
        #expect(s.slot(forMealAt: date("2026-09-02 10:30"), type: .dinner, calendar: calendar) == .dinner)
        #expect(s.slot(forMealAt: date("2026-09-02 10:00"), type: .snack, calendar: calendar) == .morningSnack)
        #expect(s.slot(forMealAt: date("2026-09-02 16:00"), type: .snack, calendar: calendar) == .afternoonSnack)
        #expect(s.slot(forMealAt: date("2026-09-02 13:00"), type: .other, calendar: calendar) == .lunch)
    }

    @Test("A later dinner moves the evening with it — on that day only")
    func movedDinner() {
        var s = MealSchedule.defaults
        s.set(.dinner, weekdays: [1], remindAt: "21:00")                  // Mondays
        #expect(s.mealType(at: date("2026-09-07 19:30"), calendar: calendar) == .dinner)   // Monday: dinner from 19:00
        #expect(s.mealType(at: date("2026-09-07 18:30"), calendar: calendar) == .snack)
        #expect(s.mealType(at: date("2026-09-08 18:30"), calendar: calendar) == .dinner)   // Tuesday: unchanged
    }

    @Test("A morning snack splits the morning only when it is switched on")
    func morningSnack() {
        var s = MealSchedule.defaults
        s.set(.breakfast, weekdays: Array(1...7), remindAt: "07:30")
        #expect(s.mealType(at: date("2026-09-02 09:30"), calendar: calendar) == .breakfast)  // a default 10:00 snack nobody asked for
        s.set(.morningSnack, weekdays: Array(1...7), enabled: true)
        #expect(s.mealType(at: date("2026-09-02 09:30"), calendar: calendar) == .snack)      // past the 08:45 midpoint
        #expect(s.mealType(at: date("2026-09-02 08:30"), calendar: calendar) == .breakfast)
    }

    @Test("A group edit touches its days, stamps the member, and only real changes travel")
    func edits() {
        let old = MealSchedule.defaults
        var s = old
        s.set(.breakfast, weekdays: [1, 2, 3, 4, 5], enabled: false)
        s.set(.lunch, weekdays: [6], remindAt: "12:00")                     // no change: stays default
        s.set(.dinner, weekdays: [7], remindAt: "not a time")               // junk ignored
        let changed = s.changes(since: old)
        #expect(changed.count == 5)
        #expect(changed.allSatisfy { $0.slot == .breakfast && $0.source == .member && !$0.enabled })
        #expect(s.entry(.breakfast, weekday: 6).enabled)
        #expect(s.entry(.lunch, weekday: 6).source == .default)
        #expect(s.entry(.dinner, weekday: 7).remindAt == "20:00")
        #expect(!s.isUniform(.breakfast, weekdays: Array(1...7)))
        #expect(s.isUniform(.breakfast, weekdays: [1, 2, 3, 4, 5]))
    }

    @Test("The setup is offered while nothing was chosen; intake and profile rows do not count as chosen")
    func awaitsSetup() {
        var s = MealSchedule(entries: [MealScheduleEntry(slot: .breakfast, weekday: 1, enabled: false, remindAt: "08:00", source: .intake),
                                       MealScheduleEntry(slot: .morningSnack, weekday: 1, enabled: true, remindAt: "10:00", source: .profile)])
        #expect(s.awaitsSetup)
        s.set(.dinner, weekdays: [3], remindAt: "20:30")
        #expect(!s.awaitsSetup)
        var confirmed = MealSchedule.defaults
        confirmed.confirmAll(as: .setup)
        #expect(!confirmed.awaitsSetup && confirmed.changes(since: .defaults).count == 35)
    }

    @Test("Wire rows: PostgREST time in, HH:mm:00 out; an unknown slot is skipped, never guessed")
    func wire() {
        let row = MealScheduleRow(patientId: "p1", slot: "afternoon_snack", weekday: 6, enabled: true, remindAt: "16:30:00", source: "profile", learningEnabled: nil, updatedVia: "engine")
        let entry = row.entry
        #expect(entry?.slot == .afternoonSnack && entry?.remindAt == "16:30" && entry?.source == .profile && entry?.learningEnabled == true)
        #expect(MealScheduleRow(patientId: nil, slot: "supper", weekday: 1, enabled: true, remindAt: "22:00:00", source: "default").entry == nil)
        #expect(MealScheduleRow(patientId: nil, slot: "lunch", weekday: 8, enabled: true, remindAt: "12:00:00", source: "default").entry == nil)
        let back = MealScheduleRow.write(MealScheduleEntry(slot: .dinner, weekday: 1, enabled: true, remindAt: "21:00", source: .member), patientId: "p1")
        #expect(back.remindAt == "21:00:00" && back.slot == "dinner" && back.source == "member" && back.updatedVia == "ios" && back.patientId == "p1")
    }

    @Test("A new meal is labelled by the member's times once known, by the clock before")
    func captureDefault() {
        let box = MealScheduleBox()
        let meals = MealService(backend: StubBackend(), calendar: calendar, schedule: box)
        let seven = date("2026-09-07 19:00")                                  // a Monday
        #expect(meals.defaultMealType(at: seven) == .dinner)                 // the clock: dinner from 18:00
        var late = MealSchedule.defaults
        late.set(.dinner, weekdays: [1], remindAt: "21:30")
        box.set(late)
        #expect(meals.defaultMealType(at: seven) == .snack)                  // their dinner starts at 19:30
        #expect(meals.defaultMealType(at: date("2026-09-07 19:30")) == .dinner)
        #expect(meals.defaultMealType(at: date("2026-09-08 19:00")) == .dinner)   // Tuesday keeps 20:00
    }
}
