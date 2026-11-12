import Foundation
import Testing
@testable import FunctionAlps

/// A `member_supplements()` answer as the server shapes it (CM OS migration 333): two supplements, one with every
/// field, one bare.
private let supplementsFixture = """
[
  {
    "id": "7f0c2b84-0000-4000-8000-000000000001",
    "care_plan_item_id": "7f0c2b84-0000-4000-8000-0000000000a1",
    "name": "Magnesium glycinate",
    "dose_text": "2 capsules",
    "units_per_moment": 2,
    "unit": "capsules",
    "moments": ["bedtime"],
    "days_rule": "daily",
    "days_of_week": null,
    "due_today": true,
    "how_to_take": ["With a glass of water.", "  ", "Keep it two hours away from your iron."],
    "why": "Helps you wind down.",
    "status": "active",
    "since": "2026-10-20",
    "prescriber_name": "Thomas",
    "client_share": {"brand": true, "composition": false, "price": false, "learn_more": false},
    "brand_label": "Pure Encapsulations Magnesium (glycinate)",
    "product_url": "https://www.galaxus.ch/en/product/1",
    "link_checked_at": "2026-11-03T09:30:00.123456+00:00",
    "today": [{"moment": "bedtime", "taken": false, "taken_at": null}],
    "observance": {
      "days": 14, "due": 14, "taken": 11, "pct": 0.79, "band": "blue",
      "strip": [
        {"date": "2026-11-11", "due": true, "today": false, "moments": [{"moment": "bedtime", "taken": true}]},
        {"date": "2026-11-12", "due": true, "today": true, "moments": [{"moment": "bedtime", "taken": false}]}
      ]
    }
  },
  {
    "id": "7f0c2b84-0000-4000-8000-000000000002",
    "name": "Iberogast",
    "moments": ["evening"],
    "days_rule": "alternate",
    "due_today": true,
    "status": "active",
    "client_share": {"brand": false, "composition": false, "price": false, "learn_more": false},
    "today": [{"moment": "evening", "taken": true, "taken_at": "2026-11-12T17:55:00Z"}],
    "observance": {"days": 14, "due": 7, "taken": 4, "pct": 0.57, "band": "orange", "strip": []}
  }
]
"""

private func decodeFixture() throws -> [Supplement] {
    try JSON.decode([Supplement].self, from: Data(supplementsFixture.utf8))
}

@Suite("Supplements — decoding the member_supplements answer")
struct SupplementDecodingTests {
    @Test("Every field of the RPC lands, camel-cased")
    func full() throws {
        let list = try decodeFixture()
        #expect(list.count == 2)
        let m = list[0]
        #expect(m.id == "7f0c2b84-0000-4000-8000-000000000001")
        #expect(m.carePlanItemId == "7f0c2b84-0000-4000-8000-0000000000a1")
        #expect(m.name == "Magnesium glycinate")
        #expect(m.doseText == "2 capsules")
        #expect(m.unitsPerMoment == 2)
        #expect(m.unit == "capsules")
        #expect(m.slots == [.bedtime])
        #expect(m.rule == .daily)
        #expect(m.daysOfWeek == nil)
        #expect(m.dueToday)
        #expect(m.isActive)
        #expect(m.since == "2026-10-20")
        #expect(m.prescriberName == "Thomas")
        #expect(m.clientShare.brand)
        #expect(!m.clientShare.price)
        #expect(m.brandLabel == "Pure Encapsulations Magnesium (glycinate)")
        #expect(m.productUrl == "https://www.galaxus.ch/en/product/1")
        #expect(m.linkCheckedAt != nil)
        #expect(m.today == [Supplement.TodayEntry(moment: "bedtime", taken: false, takenAt: nil)])
        #expect(m.observance?.taken == 11)
        #expect(m.observance?.pct == 0.79)
        #expect(m.observance?.band == "blue")
        #expect(m.observance?.strip.count == 2)
        #expect(m.observance?.strip[1].today == true)
    }

    @Test("A bare row decodes: optional fields nil, lists empty, the not-yet-served blocks absent")
    func bare() throws {
        let s = try JSON.decode([Supplement].self, from: Data(#"[{"id":"a","name":"Zinc"}]"#.utf8))[0]
        #expect(s.moments.isEmpty)
        #expect(s.slots == [.day])            // no moment listed = "any time"
        #expect(!s.dueToday)
        #expect(s.status == "active")
        #expect(s.clientShare == Supplement.ClientShare())
        #expect(s.today.isEmpty)
        #expect(s.observance == nil)
        #expect(s.whatItDoes == nil && s.composition == nil && s.priceText == nil && s.imageUrl == nil && s.learnMoreUrl == nil)
    }

    @Test("The not-yet-served fields light up when the server starts sending them")
    func futureFields() throws {
        let json = #"[{"id":"a","name":"Zinc","what_it_does":"Supports defences.","body_areas":["Immunity"],"composition":"Zinc 15 mg","price_text":"CHF 12.00","image_url":"https://img.example/z.png","learn_more_url":"https://example.org/zinc"}]"#
        let s = try JSON.decode([Supplement].self, from: Data(json.utf8))[0]
        #expect(s.whatItDoes == "Supports defences.")
        #expect(s.bodyAreas == ["Immunity"])
        #expect(s.composition == "Zinc 15 mg")
        #expect(s.priceText == "CHF 12.00")
        #expect(s.imageUrl == "https://img.example/z.png")
        #expect(s.learnMoreUrl == "https://example.org/zinc")
    }

    @Test("An unknown moment is ignored; moments come back in day order")
    func slotsOrder() {
        let s = Supplement(id: "a", name: "X", moments: ["bedtime", "nonsense", "morning"])
        #expect(s.slots == [.morning, .bedtime])
    }

    @Test("Ticking a moment sets and clears it")
    func setting() {
        let s = Supplement(id: "a", name: "X", moments: ["morning"])
        let at = Date(timeIntervalSince1970: 1_000_000)
        let on = s.setting(.morning, taken: true, at: at)
        #expect(on.isTaken(.morning))
        #expect(on.takenAt(.morning) == at)
        let off = on.setting(.morning, taken: false)
        #expect(!off.isTaken(.morning))
        #expect(off.takenAt(.morning) == nil)
    }
}

@Suite("Supplements — the moment of the day, Home's rows, the written adherence")
struct SupplementLogicTests {
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

    @Test("The current moment: morning until 11:00, midday until 15:00, evening until 21:00, then the night")
    func currentMoment() {
        #expect(SupplementLogic.currentMoment(hour: 6) == .morning)
        #expect(SupplementLogic.currentMoment(hour: 10) == .morning)
        #expect(SupplementLogic.currentMoment(hour: 11) == .noon)
        #expect(SupplementLogic.currentMoment(hour: 14) == .noon)
        #expect(SupplementLogic.currentMoment(hour: 15) == .evening)
        #expect(SupplementLogic.currentMoment(hour: 20) == .evening)
        #expect(SupplementLogic.currentMoment(hour: 21) == .bedtime)
        #expect(SupplementLogic.currentMoment(hour: 23) == .bedtime)
        #expect(SupplementLogic.currentMoment(at: date("2026-11-12 14:59"), calendar: calendar) == .noon)
        #expect(SupplementLogic.currentMoment(at: date("2026-11-12 15:00"), calendar: calendar) == .evening)
    }

    @Test("Display names")
    func names() {
        #expect(SupplementMoment.morning.displayName == "Morning")
        #expect(SupplementMoment.noon.displayName == "Midday")
        #expect(SupplementMoment.evening.displayName == "Evening")
        #expect(SupplementMoment.bedtime.displayName == "Night")
        #expect(SupplementMoment.day.displayName == "Any time")
    }

    @Test("Dose: the practice's words first, else units and unit")
    func dose() {
        #expect(SupplementLogic.doseText(Supplement(id: "a", name: "X", doseText: " 20 drops before dinner ")) == "20 drops before dinner")
        #expect(SupplementLogic.doseText(Supplement(id: "a", name: "X", unitsPerMoment: 2, unit: "capsules")) == "2 capsules")
        #expect(SupplementLogic.doseText(Supplement(id: "a", name: "X", unitsPerMoment: 1.5, unit: "scoops")) == "1.5 scoops")
        #expect(SupplementLogic.doseText(Supplement(id: "a", name: "X")) == nil)
        #expect(SupplementLogic.doseLine(Supplement(id: "a", name: "X", doseText: "2 capsules", moments: ["bedtime"])) == "2 capsules · Night")
    }

    @Test("Home rows: only active supplements due today, one per moment, in day order, the current moment flagged")
    func rows() throws {
        let list = [
            Supplement(id: "n", name: "Magnesium", doseText: "2 capsules", moments: ["bedtime"]),
            Supplement(id: "m", name: "Probiotic", moments: ["morning"], today: [.init(moment: "morning", taken: true, takenAt: nil)]),
            Supplement(id: "x", name: "Not today", moments: ["morning"], dueToday: false),
            Supplement(id: "p", name: "Paused", moments: ["morning"], status: "paused"),
            Supplement(id: "t", name: "Twice", moments: ["morning", "evening"]),
        ]
        let rows = SupplementLogic.rows(list, now: date("2026-11-12 08:30"), calendar: calendar)
        #expect(rows.map(\.id) == ["m.morning", "t.morning", "t.evening", "n.bedtime"])
        #expect(rows.map(\.isCurrent) == [true, true, false, false])
        #expect(rows[0].taken)
        #expect(!rows[1].taken)
        #expect(rows[3].dose == "2 capsules")
        #expect(SupplementLogic.progressText(rows) == "1 of 4 taken")
        // Later in the day the highlight moves.
        let evening = SupplementLogic.rows(list, now: date("2026-11-12 19:00"), calendar: calendar)
        #expect(evening.filter(\.isCurrent).map(\.id) == ["t.evening"])
    }

    @Test("Adherence is written: '11 of 14 days' daily, '4 of 7 due' otherwise; the percent beside it")
    func adherence() {
        let daily = Supplement.Observance(days: 14, due: 14, taken: 11, pct: 0.786, band: "blue", strip: [])
        #expect(SupplementLogic.adherenceText(daily, rule: .daily) == "11 of 14 days")
        #expect(SupplementLogic.percentText(daily) == "79%")
        #expect(SupplementLogic.adherenceSpoken(daily, rule: .daily) == "11 of 14 days, 79 percent")
        let alternate = Supplement.Observance(days: 14, due: 7, taken: 4, pct: 4.0 / 7.0, band: "orange", strip: [])
        #expect(SupplementLogic.adherenceText(alternate, rule: .alternate) == "4 of 7 due")
        #expect(SupplementLogic.adherenceText(alternate, rule: .weekdays) == "4 of 7 due")
        let fresh = Supplement.Observance(days: 0, due: 0, taken: 0, pct: nil, band: nil, strip: [])
        #expect(SupplementLogic.adherenceText(fresh, rule: .daily) == nil)
        #expect(SupplementLogic.adherenceText(fresh, rule: .alternate) == nil)
        #expect(SupplementLogic.percentText(fresh) == nil)
        #expect(SupplementLogic.band(daily) == .blue)
        #expect(SupplementLogic.band(fresh) == nil)
    }

    @Test("The strip's marks are told apart by what happened, not by colour")
    func strip() {
        func day(due: Bool = true, today: Bool = false, _ taken: [Bool]) -> Supplement.StripDay {
            Supplement.StripDay(date: "2026-11-12", due: due, today: today, moments: taken.map { Supplement.StripDay.Entry(moment: "morning", taken: $0) })
        }
        #expect(SupplementLogic.mark(day(due: false, [])) == .notDue)
        #expect(SupplementLogic.mark(day([true])) == .taken)
        #expect(SupplementLogic.mark(day([true, true])) == .taken)
        #expect(SupplementLogic.mark(day([true, false])) == .partial)
        #expect(SupplementLogic.mark(day([false])) == .missed)
        #expect(SupplementLogic.mark(day(today: true, [false])) == .pending)
        #expect(SupplementLogic.mark(day(today: true, [true])) == .taken)
    }

    @Test("The Plan list: active by their first moment, paused last")
    func planOrder() {
        let list = [
            Supplement(id: "p", name: "Paused", moments: ["morning"], status: "paused"),
            Supplement(id: "n", name: "Magnesium", moments: ["bedtime"]),
            Supplement(id: "m", name: "Probiotic", moments: ["morning"]),
        ]
        #expect(SupplementLogic.planOrder(list).map(\.id) == ["m", "n", "p"])
    }

    @Test("The reminder line on a supplement's page")
    func reminderLine() {
        var prefs = NotificationPrefs.default
        let one = Supplement(id: "a", name: "X", moments: ["bedtime"])
        let two = Supplement(id: "b", name: "Y", moments: ["morning", "evening"])
        let anytime = Supplement(id: "c", name: "Z", moments: ["day"])
        #expect(SupplementLogic.reminderLine(one, prefs: prefs) == "Reminder at 22:00")
        #expect(SupplementLogic.reminderLine(two, prefs: prefs) == "Reminders at 08:00, 19:00")
        #expect(SupplementLogic.reminderLine(anytime, prefs: prefs) == nil)
        #expect(SupplementLogic.reminderLine(Supplement(id: "d", name: "P", moments: ["morning"], status: "paused"), prefs: prefs) == nil)
        prefs.supplementRemindersEnabled = false
        #expect(SupplementLogic.reminderLine(one, prefs: prefs) == "Reminders are off")
    }
}

@Suite("Supplements — what a supplement's page shows")
struct SupplementPageBlocksTests {
    @Test("Not-yet-served blocks are absent: no body effect, no composition, no price, no image, no learn more")
    func hiddenWhenAbsent() throws {
        let m = try decodeFixture()[0]
        #expect(SupplementPageBlocks.bodyEffect(m) == nil)
        let brand = SupplementPageBlocks.brand(m)
        #expect(brand?.label == "Pure Encapsulations Magnesium (glycinate)")
        #expect(brand?.buyURL?.host == "www.galaxus.ch")
        #expect(brand?.checked != nil)
        #expect(brand?.composition == nil && brand?.price == nil && brand?.imageURL == nil && brand?.learnMoreURL == nil)
        #expect(SupplementPageBlocks.howToTake(m) == ["With a glass of water.", "Keep it two hours away from your iron."])
        #expect(SupplementPageBlocks.why(m) == "Helps you wind down.")
        #expect(SupplementPageBlocks.prescribed(m)?.name == "Thomas")
        #expect(SupplementPageBlocks.prescribed(m)?.since != nil)
    }

    @Test("A supplement the practice shares nothing about has no brand card; a bare one has no prescribed card")
    func notShared() throws {
        let iberogast = try decodeFixture()[1]
        #expect(SupplementPageBlocks.brand(iberogast) == nil)
        #expect(SupplementPageBlocks.prescribed(iberogast) == nil)
        #expect(SupplementPageBlocks.why(iberogast) == nil)
        #expect(SupplementPageBlocks.howToTake(iberogast).isEmpty)
    }

    @Test("Shared parts appear only when shared AND sent; only https links leave the app")
    func shareFlags() {
        var s = Supplement(id: "a", name: "X", clientShare: .none, brandLabel: "Brand", productUrl: "https://shop.example/x")
        s.composition = "Zinc 15 mg"
        s.priceText = "CHF 12.00"
        #expect(SupplementPageBlocks.brand(s) == nil)       // nothing shared
        s.clientShare.brand = true
        #expect(SupplementPageBlocks.brand(s)?.label == "Brand")
        #expect(SupplementPageBlocks.brand(s)?.price == nil && SupplementPageBlocks.brand(s)?.composition == nil)
        s.clientShare.price = true
        s.clientShare.composition = true
        #expect(SupplementPageBlocks.brand(s)?.price == "CHF 12.00")
        #expect(SupplementPageBlocks.brand(s)?.composition == "Zinc 15 mg")
        s.productUrl = "http://insecure.example/x"
        #expect(SupplementPageBlocks.brand(s)?.buyURL == nil)
        s.bodyAreas = ["Muscles", " "]
        s.whatItDoes = "  "
        #expect(SupplementPageBlocks.bodyEffect(s) == SupplementPageBlocks.BodyEffect(text: nil, areas: ["Muscles"]))
    }
}

@Suite("Supplements — the grouped reminders")
struct SupplementReminderTests {
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

    // Thursday 12 Nov 2026, 09:00.
    private var now: Date { date("2026-11-12 09:00") }

    private func plan(_ list: [Supplement], prefs: NotificationPrefs = .default, now: Date? = nil) -> [NotificationPlanner.Planned] {
        SupplementReminders.plan(supplements: list, prefs: prefs, now: now ?? self.now, calendar: calendar)
    }

    private let iberogast = Supplement(id: "i", name: "Iberogast", doseText: "20 drops before dinner", moments: ["evening"])
    private let magnesium = Supplement(id: "m", name: "Magnesium", doseText: "2 capsules", moments: ["evening", "bedtime"])

    @Test("One grouped reminder per moment, at the member's time: 'Evening: Iberogast, Magnesium'")
    func grouped() {
        let today = plan([iberogast, magnesium]).filter { $0.id.contains("2026-11-12") }
        #expect(today.count == 2)
        let evening = today.first { $0.extra["moment"] == "evening" }
        #expect(evening?.title == "Evening: Iberogast, Magnesium")
        #expect(evening?.body == "2 supplements to take.")
        #expect(evening?.fireAt == date("2026-11-12 19:00"))
        #expect(evening?.kind == .supplements)
        #expect(evening?.route == "functionalps://supplements")
        #expect(evening?.extra["ids"] == "i,m")
        #expect(evening?.extra["day"] == "2026-11-12")
        let night = today.first { $0.extra["moment"] == "bedtime" }
        #expect(night?.title == "Night: Magnesium")
        #expect(night?.body == "2 capsules")
        #expect(night?.fireAt == date("2026-11-12 21:45"))     // 22:00 sits at the quiet window's edge: 15 minutes before
    }

    @Test("A single supplement's body is its dose")
    func singleBody() {
        let p = plan([iberogast]).first
        #expect(p?.title == "Evening: Iberogast")
        #expect(p?.body == "20 drops before dinner")
    }

    @Test("Only on days something is due, and never for a moment already ticked")
    func dueOnly() {
        var notDue = iberogast
        notDue.dueToday = false
        #expect(plan([notDue]).filter { $0.id.contains("2026-11-12") }.isEmpty)
        var ticked = magnesium
        ticked.today = [.init(moment: "evening", taken: true, takenAt: nil)]
        let today = plan([ticked]).filter { $0.id.contains("2026-11-12") }
        #expect(today.map { $0.extra["moment"] } == ["bedtime"])
        var paused = iberogast
        paused.status = "paused"
        #expect(plan([paused]).isEmpty)
    }

    @Test("A moment already past today is not planned; later days follow only for daily supplements")
    func horizon() {
        let morning = Supplement(id: "a", name: "Probiotic", moments: ["morning"])
        let late = plan([morning], now: date("2026-11-12 08:30"))
        #expect(late.filter { $0.id.contains("2026-11-12") }.isEmpty)                  // 08:00 has gone
        #expect(late.map { $0.extra["day"] } == ["2026-11-13", "2026-11-14"])
        var alternate = morning
        alternate.daysRule = "alternate"
        #expect(plan([alternate], now: date("2026-11-12 06:00")).map { $0.extra["day"] } == ["2026-11-12"])   // tomorrow unknown
    }

    @Test("Any-time supplements have no moment, so no reminder")
    func anyTime() {
        #expect(plan([Supplement(id: "a", name: "Zinc", moments: ["day"])]).isEmpty)
    }

    @Test("Switched off in the preferences: nothing planned")
    func off() {
        var prefs = NotificationPrefs.default
        prefs.supplementRemindersEnabled = false
        #expect(plan([iberogast], prefs: prefs).isEmpty)
    }

    @Test("The member's own times; quiet hours move a morning reminder to the window's end")
    func timesAndQuiet() {
        var prefs = NotificationPrefs.default
        prefs.supplementTimes.set("18:30", for: .evening)
        prefs.supplementTimes.set("07:00", for: .morning)       // inside quiet hours 22:00–07:30
        let morning = Supplement(id: "a", name: "Probiotic", moments: ["morning"])
        let p = plan([iberogast, morning], prefs: prefs, now: date("2026-11-12 06:00")).filter { $0.id.contains("2026-11-12") }
        #expect(p.first { $0.extra["moment"] == "evening" }?.fireAt == date("2026-11-12 18:30"))
        #expect(p.first { $0.extra["moment"] == "morning" }?.fireAt == date("2026-11-12 07:30"))
        prefs.quietHoursEnabled = false
        let free = plan([morning], prefs: prefs, now: date("2026-11-12 06:00")).filter { $0.id.contains("2026-11-12") }
        #expect(free.first?.fireAt == date("2026-11-12 07:00"))
    }

    @Test("A changed set of supplements is a new request id, so the phone replaces the pending one")
    func ids() {
        let a = plan([iberogast]).first?.id
        let b = plan([iberogast, magnesium]).first { $0.extra["moment"] == "evening" }?.id
        #expect(a != nil && b != nil && a != b)
        #expect(plan([iberogast]).first?.id == a)            // stable
        #expect(a?.hasPrefix("supp.evening.2026-11-12.1900.") == true)
        #expect(!(a ?? "").hasPrefix("supp.later."))
    }

    @Test("The planner carries the supplement reminders, quiet hours keep them, and 'Taken' reads its group back")
    func integration() {
        var state = NotificationPlanner.State(now: now)
        state.supplements = [iberogast]
        let full = NotificationPlanner.respectingQuietHours(NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar), prefs: .default, calendar: calendar)
        let supp = full.filter { $0.kind == .supplements }
        #expect(supp.count == 3)                                // today + two days, a daily supplement
        #expect(supp.allSatisfy { $0.extra["moment"] == "evening" })
        let group = SupplementReminders.group(moment: supp[0].extra["moment"], day: supp[0].extra["day"], ids: supp[0].extra["ids"])
        #expect(group == SupplementReminders.Group(moment: .evening, day: "2026-11-12", supplementIds: ["i"]))
        #expect(SupplementReminders.group(moment: "evening", day: nil, ids: "i") == nil)
        #expect(SupplementReminders.group(moment: "nonsense", day: "2026-11-12", ids: "i") == nil)
        #expect(SupplementReminders.group(moment: "evening", day: "2026-11-12", ids: "") == nil)
        // No supplements, no supplement reminders.
        let none = NotificationPlanner.plan(prefs: .default, state: NotificationPlanner.State(now: now), calendar: calendar)
        #expect(none.allSatisfy { $0.kind != .supplements })
    }
}

@Suite("Supplements — the reminder preferences row")
struct SupplementPrefsTests {
    @Test("The row's jsonb times decode; a missing or junk time falls back to the default")
    func decode() throws {
        let json = #"{"patient_id":"p","supplement_reminders_enabled":false,"supplement_times":{"morning":"07:15:00","noon":"junk","evening":"19:00"}}"#
        let row = try JSON.decode(NotificationPrefsRow.self, from: Data(json.utf8))
        let prefs = row.prefs
        #expect(!prefs.supplementRemindersEnabled)
        #expect(prefs.supplementTimes.morning == "07:15")
        #expect(prefs.supplementTimes.noon == "12:30")
        #expect(prefs.supplementTimes.evening == "19:00")
        #expect(prefs.supplementTimes.bedtime == "22:00")
    }

    @Test("Reminders are on by default, at the four default times; a row without the columns keeps them")
    func defaults() throws {
        let prefs = NotificationPrefs.default
        #expect(prefs.supplementRemindersEnabled)
        #expect(prefs.supplementTimes.time(for: .morning) == "08:00")
        #expect(prefs.supplementTimes.time(for: .noon) == "12:30")
        #expect(prefs.supplementTimes.time(for: .evening) == "19:00")
        #expect(prefs.supplementTimes.time(for: .bedtime) == "22:00")
        let bare = try JSON.decode(NotificationPrefsRow.self, from: Data(#"{"patient_id":"p"}"#.utf8)).prefs
        #expect(bare.supplementRemindersEnabled)
        #expect(bare.supplementTimes == SupplementTimes())
    }

    @Test("The write carries the supplement switch and times, and the select asks for them")
    func write() {
        var prefs = NotificationPrefs.default
        prefs.supplementRemindersEnabled = false
        prefs.supplementTimes.set("21:30", for: .bedtime)
        let row = NotificationPrefsRow.write(prefs, patientId: "p")
        #expect(row.supplementRemindersEnabled == false)
        #expect(row.supplementTimes?.bedtime == "21:30")
        #expect(NotificationPrefsRow.columns.contains("supplement_reminders_enabled"))
        #expect(NotificationPrefsRow.columns.contains("supplement_times"))
    }
}
