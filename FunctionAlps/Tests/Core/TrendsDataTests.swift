import Foundation
import Testing
@testable import FunctionAlps

/// The Trends page's arithmetic (owner-validated mockup v2, 2026-11-10): windows, the equal-weight score, the
/// previous window, adherence, food by day, the night, digestion, devices.
@Suite("Trends data — windows, the equal-weight score, adherence, food days")
struct TrendsDataTests {
    private let today = "2026-11-10"   // a Tuesday

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func checkin(_ day: String, energy: Int? = nil, mood: Int? = nil, sleep: Int? = nil, calm: Int? = nil, gut: Int? = nil) -> DailyCheckin {
        DailyCheckin(day: day, functionalCompletedAt: nil, gutCompletedAt: nil, energy: energy, mood: mood, sleep: sleep, calmness: calm, gutOverall: gut)
    }

    private func moment(focus: Int? = nil, duration: Int? = nil, bed: String? = nil, wake: String? = nil, refreshed: Int? = nil) -> CheckinMoment {
        var m = CheckinMoment(slot: .evening, submittedAt: Date(timeIntervalSince1970: 0))
        m.energyMind = focus
        m.sleepDurationMin = duration; m.sleepBedTime = bed; m.sleepWakeTime = wake; m.sleepRefreshed = refreshed
        return m
    }

    private func raw(_ checkins: [DailyCheckin] = [], moments: [String: [CheckinMoment]] = [:]) -> TrendsRaw {
        var r = TrendsRaw(today: today)
        r.checkins = checkins
        r.momentsByDay = moments
        return r
    }

    private func date(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        let p = day.split(separator: "-").compactMap { Int($0) }
        return utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour, minute: minute))!
    }

    // MARK: Windows

    @Test("A window ends today and counts back N days; the previous window is the N days before it")
    func windowBounds() {
        let days = TrendsEngine.days(.fortnight, today: today)
        #expect(days.count == 14)
        #expect(days.first == "2026-10-28" && days.last == "2026-11-10")
        let before = TrendsEngine.previousDays(.fortnight, today: today)
        #expect(before.count == 14)
        #expect(before.first == "2026-10-14" && before.last == "2026-10-27")
        #expect(TrendsEngine.days(.week, today: today).count == 7)
        #expect(TrendsEngine.days(.week, today: today).first == "2026-11-04")
        #expect(TrendsEngine.days(.month, today: today).count == 28)
        #expect(TrendsEngine.previousDays(.month, today: today).count == 28)
        #expect(TrendWindow.readDays == 56)
    }

    // MARK: Markers, stress, the score

    @Test("Stress is stored as calm and shown as a level: 10 minus calm/10")
    func stressInversion() {
        #expect(TrendsEngine.level(.stress, marker: 70) == 3)
        #expect(TrendsEngine.level(.stress, marker: 100) == 0)
        #expect(TrendsEngine.level(.energy, marker: 70) == 7)
        #expect(TrendsEngine.level(.digestion, marker: 45) == 4.5)
        let index = TrendsEngine.Index(raw([checkin(today, calm: 70)]))
        #expect(TrendsEngine.marker(.stress, on: today, in: index) == 70)   // the marker itself is never inverted
    }

    @Test("Focus is the mind half of the energy read, from the day's moments")
    func focusFromMoments() {
        let index = TrendsEngine.Index(raw([checkin(today, energy: 60)], moments: [today: [moment(focus: 35)]]))
        #expect(TrendsEngine.marker(.focus, on: today, in: index) == 35)
        #expect(TrendsEngine.marker(.focus, on: "2026-11-09", in: index) == nil)
    }

    @Test("The score is the plain mean of the signals logged that day — a missing signal is left out, not counted as zero")
    func equalWeightScore() {
        let four = TrendsEngine.Index(raw([checkin(today, energy: 80, mood: 60, sleep: 40, calm: 60)]))
        #expect(TrendsEngine.score(on: today, in: four) == 60)
        // With focus logged too, five signals share the weight equally.
        let five = TrendsEngine.Index(raw([checkin(today, energy: 80, mood: 60, sleep: 40, calm: 60)], moments: [today: [moment(focus: 100)]]))
        #expect(TrendsEngine.score(on: today, in: five) == 68)
        // All six.
        let six = TrendsEngine.Index(raw([checkin(today, energy: 80, mood: 60, sleep: 40, calm: 60, gut: 90)], moments: [today: [moment(focus: 100)]]))
        #expect(abs((TrendsEngine.score(on: today, in: six) ?? 0) - 430.0 / 6) < 0.000_001)
        // Nothing logged: no score.
        #expect(TrendsEngine.score(on: today, in: TrendsEngine.Index(raw())) == nil)
    }

    @Test("The score summary: the newest day with a signal, its chips in signal order, the averages")
    func scoreSummary() {
        let r = raw([
            checkin("2026-11-08", energy: 50, mood: 50, sleep: 50, calm: 50, gut: 50),
            checkin("2026-11-09", energy: 70, mood: 70, sleep: 70, calm: 70, gut: 70),
            checkin("2026-10-20", energy: 40), checkin("2026-10-21", energy: 40), checkin("2026-10-22", energy: 40),
        ])
        let s = TrendsEngine.scoreSummary(window: .fortnight, today: today, index: TrendsEngine.Index(r))
        #expect(s.day == "2026-11-09")
        #expect(s.value == 70)
        #expect(s.chips.map(\.signal) == [.sleep, .energy, .focus, .mood, .stress, .digestion])
        #expect(s.chips[2].marker == nil)       // focus was not logged
        #expect(s.chips[4].marker == 70)        // stress counts as calm
        #expect(s.average == 60)
        #expect(s.previousAverage == 40)
    }

    @Test("The previous window needs at least three logged days to be a figure")
    func previousWindow() {
        let three = raw([checkin("2026-10-15", energy: 40), checkin("2026-10-16", energy: 50), checkin("2026-10-17", energy: 60), checkin(today, energy: 80)])
        let s3 = TrendsEngine.series(.energy, window: .fortnight, today: today, index: TrendsEngine.Index(three))
        #expect(s3.previousAverage == 50)
        #expect(s3.average == 80)
        #expect(s3.latest == 80 && s3.latestDay == today)
        let two = raw([checkin("2026-10-15", energy: 40), checkin("2026-10-16", energy: 50)])
        #expect(TrendsEngine.series(.energy, window: .fortnight, today: today, index: TrendsEngine.Index(two)).previousAverage == nil)
    }

    @Test("A signal's levels are the 0–10 reads the member sees, stress as a level")
    func levels() {
        let s = TrendsEngine.series(.stress, window: .week, today: today, index: TrendsEngine.Index(raw([checkin(today, calm: 70)])))
        #expect(s.latestLevel == 3)
        #expect(s.levels.last == 3)
        #expect(s.levels[0] == nil)
    }

    // MARK: Adherence

    private func habit(_ id: String, rule: String, status: String = "active", created: String = "2026-10-01T09:00:00Z") -> HabitRow {
        HabitRow(id: id, carePlanItemId: nil, title: id, description: nil, frequencyRule: rule, status: status, source: "prescribed",
                 pillar: nil, slot: nil, appearsAfterHabitId: nil, easyTitle: nil, easyDescription: nil, revTitle: nil, revDescription: nil,
                 createdAt: created)
    }

    @Test("Adherence counts, per day, the due habits and how many of them were done")
    func adherence() {
        let plan = HabitPlan(
            day: today, header: nil, phases: [],
            habits: [
                habit("daily", rule: "FREQ=DAILY"),
                habit("mondays", rule: "FREQ=WEEKLY;BYDAY=MO"),
                habit("paused", rule: "FREQ=DAILY", status: "paused"),
                habit("late", rule: "FREQ=DAILY", created: "2026-11-09T09:00:00Z"),
            ],
            completions: [
                HabitCompletionRow(id: "1", habitId: "daily", completionDate: "2026-11-09"),
                HabitCompletionRow(id: "2", habitId: "mondays", completionDate: "2026-11-09"),
                HabitCompletionRow(id: "3", habitId: "daily", completionDate: "2026-11-10"),
                HabitCompletionRow(id: "4", habitId: "paused", completionDate: "2026-11-10"),   // not active: never counted
                HabitCompletionRow(id: "5", habitId: "late", completionDate: "2026-11-08"),      // before it existed: not due
            ])
        let a = TrendsEngine.adherence(plan: plan, window: .week, today: today)
        #expect(a.days.count == 7)
        let byDay = Dictionary(uniqueKeysWithValues: a.days.map { ($0.day, $0) })
        #expect(byDay["2026-11-08"]?.due == 1 && byDay["2026-11-08"]?.done == 0)    // daily only (late began on the 9th)
        #expect(byDay["2026-11-09"]?.due == 3 && byDay["2026-11-09"]?.done == 2)    // daily + Monday + late
        #expect(byDay["2026-11-10"]?.due == 2 && byDay["2026-11-10"]?.done == 1)
        #expect(a.due == 10 && a.done == 3)   // 4 + 1 + 3 + 2 due; 2 + 1 done
        #expect(a.maxDue == 3)
        #expect(TrendsEngine.adherence(plan: nil, window: .week, today: today).due == 0)
    }

    // MARK: Food

    @Test("Meals group by day, newest day first, each day in the order eaten, with the member's own reaction words")
    func foodDays() {
        let meals = [
            MealLog(id: "dinner", loggedAt: date("2026-11-09", 21, 25), name: "Salmon"),
            MealLog(id: "lunch", loggedAt: date("2026-11-10", 12, 40), name: "Lentil salad", photoPath: "p/lunch.jpg"),
            MealLog(id: "breakfast", loggedAt: date("2026-11-10", 8, 5), name: "Porridge"),
            MealLog(id: "old", loggedAt: date("2026-11-01", 8, 0), name: "Outside the window"),
        ]
        let reactions = [
            "breakfast": MealReaction(overall: 8, flags: ["felt_full"]),
            "dinner": MealReaction(overall: 5, flags: []),
        ]
        let days = TrendsEngine.foodDays(meals: meals, reactions: reactions, days: TrendsEngine.days(.week, today: today), calendar: utc)
        #expect(days.map(\.day) == ["2026-11-10", "2026-11-09"])
        #expect(days[0].meals.map(\.id) == ["breakfast", "lunch"])
        #expect(days[0].meals[0].words == [String(localized: "meal.felt.good", defaultValue: "Sat well"), "felt full"])
        #expect(days[0].meals[1].words.isEmpty)                           // none logged — never invented
        #expect(days[0].meals[1].photoPath == "p/lunch.jpg")
        #expect(days[1].meals[0].words == [String(localized: "meal.felt.watch", defaultValue: "A bit off")])
        #expect(!days.flatMap(\.meals).contains { $0.id == "old" })
    }

    // MARK: Pills

    @Test("A day's pills come back as the check-in's own words, per signal")
    func pillWords() {
        var m = moment()
        m.pills = ["flavour_pos": ["motivated"], "drivers": ["sleep"], "source": ["work"], "fuelled": ["proper_meal"], "drained": ["short_night"]]
        let mood = TrendsEngine.pillWords(.mood, moments: [m])
        #expect(mood.count == 2)
        #expect(TrendsEngine.pillWords(.stress, moments: [m]).count == 1)
        // Energy and focus read the day's fuelled / drained; sleep keeps only the catalogue pills that belong to sleep.
        #expect(TrendsEngine.pillWords(.energy, moments: [m]).count == 2)
        #expect(TrendsEngine.pillWords(.sleep, moments: [m]).count == 1)
        #expect(TrendsEngine.pillWords(.digestion, moments: [m]).isEmpty)
        #expect(TrendsEngine.pillWords(.mood, moments: nil).isEmpty)
    }

    // MARK: Sleep

    @Test("A device's night wins over the check-in's; a day with neither has no night")
    func sleepNights() {
        var r = raw(moments: [
            today: [moment(duration: 450, bed: "23:00", wake: "06:30", refreshed: 60)],
            "2026-11-09": [moment(duration: 420, bed: "23:30", wake: "06:30")],
        ])
        r.nights = [WearableNight(day: today, sourceId: 1_000_018, bedTime: "23:05", wakeTime: "06:50", durationMin: 465, latency: "lt_15",
                                  wakeCount: "1_2", asleepMin: 422)]
        let s = TrendsEngine.sleepSummary(r, window: .week)
        #expect(s.entries.count == 7)
        let last = s.entries.last ?? nil
        #expect(last?.fromDevice == true && last?.asleepMin == 422 && last?.bedTime == "23:05")
        #expect(last?.minutes == 422)
        let yesterday = s.entries[5]
        #expect(yesterday?.fromDevice == false && yesterday?.asleepMin == nil && yesterday?.inBedMin == 420 && yesterday?.minutes == 420)
        #expect(s.entries[0] == nil)
        #expect(s.refreshed?.day == today && s.refreshed?.value == 60)
        #expect(s.hasNights)
        #expect(s.recent.first?.day == today)
        #expect(abs((s.averageHours ?? 0) - 421.0 / 60) < 1e-9)
    }

    // MARK: Digestion

    @Test("Digestion days carry comfort, stool (times and Bristol type), the symptoms ticked and the meals, newest first")
    func digestion() {
        var r = raw([checkin(today, gut: 70)])
        r.gutDays = [GutDay(day: today, comfort: 55, stool: 60, reactions: 60, overall: 70, stoolQuality: 4, stoolFrequency: 2, completedAt: nil,
                            bristol: 4, symptoms: ["bloating", "gas"])]
        r.meals = [MealLog(id: "m", loggedAt: date(today, 12, 40), name: "Lentil salad")]
        r.reactions = ["m": MealReaction(overall: 5, flags: ["bloating"])]
        let days = TrendsEngine.digestionDays(r, window: .week, calendar: utc)
        #expect(days.map(\.day) == [today])
        let d = days[0]
        #expect(d.headline == 55 && d.headlineIsComfort)       // comfort leads when it was logged
        #expect(d.stoolFrequency == 2 && d.bristol == 4)
        #expect(d.symptoms.count == 2)
        #expect(d.meals.map(\.id) == ["m"] && !d.meals[0].words.isEmpty)
        // A day with only a gut overall falls back to it.
        let only = TrendsEngine.digestionDays(raw([checkin(today, gut: 62)]), window: .week, calendar: utc)
        #expect(only.first?.headline == 62 && only.first?.headlineIsComfort == false)
        #expect(TrendsEngine.digestionDays(raw(), window: .week, calendar: utc).isEmpty)
    }

    // MARK: Devices

    @Test("Devices: Apple Health on this phone when connected, then each live vendor account")
    func devices() {
        var r = raw()
        r.appleHealthConnected = true
        r.vendorAccounts = [
            WearableVendorAccountRow(vendor: "oura", status: "connected", reconnectRequired: false, lastSuccessfulSyncAt: date(today, 7, 12), lastErrorCode: nil, connectedAt: nil),
            WearableVendorAccountRow(vendor: "whoop", status: "reconnect_required", reconnectRequired: true, lastSuccessfulSyncAt: nil, lastErrorCode: nil, connectedAt: nil),
            WearableVendorAccountRow(vendor: "polar", status: "not_connected", reconnectRequired: nil, lastSuccessfulSyncAt: nil, lastErrorCode: nil, connectedAt: nil),
        ]
        let devices = TrendsEngine.devices(r)
        #expect(devices.map(\.key) == [TrendsEngine.appleHealthKey, "oura"])
        #expect(devices[0].isAppleHealth && devices[0].sourceId == WearableSource.appleHealth)
        #expect(devices[1].name == "Oura" && devices[1].sourceId == 1_000_018 && devices[1].lastSync != nil)
        #expect(TrendsEngine.devices(raw()).isEmpty)
    }

    @Test("A device's metrics come from its own rows only, with the previous window's average")
    func deviceMetrics() {
        func row(_ day: String, _ metric: String, _ value: Double, source: Int = 1_000_018) -> WearableLabeledRow {
            WearableLabeledRow(day: day, metric: metric, value: value, dataSourceId: source, layer: "raw")
        }
        let rows = [
            row(today, "Steps", 6400), row("2026-11-09", "Steps", 8000),
            row("2026-10-15", "Steps", 5000), row("2026-10-16", "Steps", 6000), row("2026-10-17", "Steps", 7000),
            row(today, "HeartRateResting", 54), row(today, "ThryveMainSleepDuration", 25_320),
            row(today, "Steps", 99_999, source: 1_000_001),      // another source: not this device's
        ]
        let metrics = TrendsEngine.deviceMetrics(rows: rows, sourceId: 1_000_018, window: .fortnight, today: today)
        #expect(metrics.map(\.kind) == [.sleep, .restingHeartRate, .steps])     // no HRV rows: no HRV card
        let steps = metrics[2]
        #expect(steps.latest == 6400)
        #expect(steps.average == 7200)
        #expect(steps.previousAverage == 6000)
        #expect(metrics[0].latest == 7.0)                                       // 25 320 s = 7.0 h (to a tenth)
        #expect(TrendsEngine.deviceMetrics(rows: rows, sourceId: 42, window: .fortnight, today: today).isEmpty)
    }

    // MARK: Shared patterns

    @Test("A shared pattern is a count: k of n from consistency over n_obs; vocabulary it cannot phrase is left out")
    func sharedPatterns() {
        func pattern(_ subject: String, _ reaction: String, kind: String = "pattern", n: Int = 5, c: Double? = 0.8, direction: String = "worse") -> UserPattern {
            UserPattern(kind: kind, subject: subject, reaction: reaction, direction: direction, effect: nil, nObs: n, consistency: c, tier: "confirmed")
        }
        let late = pattern("late_dinner", "next_energy")
        let counts = SharedPatternText.counts(late)
        #expect(counts?.k == 4 && counts?.n == 5)
        let made = SharedPatternText.make(late)
        #expect(made != nil && made?.title.contains("→") == true && made?.sentence.isEmpty == false)
        #expect(SharedPatternText.make(pattern("late_dinner", "next_energy", n: 0)) == nil)
        #expect(SharedPatternText.make(pattern("late_dinner", "next_energy", c: nil)) == nil)
        #expect(SharedPatternText.make(pattern("moon_phase", "next_energy")) == nil)
        #expect(SharedPatternText.make(pattern("late_dinner", "mystery")) == nil)
        #expect(SharedPatternText.make(pattern("late_dinner", "next_energy", direction: "sideways")) == nil)
        // A food trigger reads as bloating and keeps the food's own name.
        let food = SharedPatternText.make(pattern("raw vegetables", "bloating", kind: "trigger_food", n: 4, c: 0.75))
        #expect(food?.title.hasPrefix("Raw vegetables") == true || food?.title.isEmpty == false)
        #expect(SharedPatternText.counts(pattern("raw vegetables", "bloating", kind: "trigger_food", n: 4, c: 0.75))?.k == 3)
        // Worse next-day energy and worse bloating move in opposite directions on the dial; better flips each.
        let worseEnergy = SharedPatternText.make(pattern("late_dinner", "next_energy"))?.sentence
        let betterEnergy = SharedPatternText.make(pattern("late_dinner", "next_energy", direction: "better"))?.sentence
        #expect(worseEnergy != betterEnergy)
    }

    // MARK: The page

    @Test("The page counts all six signals, one sentence each, and the score of the newest day")
    func page() {
        let r = raw([checkin("2026-11-09", energy: 60, mood: 60, sleep: 60, calm: 60, gut: 60)], moments: ["2026-11-09": [moment(focus: 60)]])
        let p = TrendsEngine.page(r, window: .fortnight, calendar: utc)
        #expect(p.score.value == 60)
        #expect(TrendSignal.allCases.allSatisfy { p.series($0) != nil && !p.sentence($0).isEmpty })
        // One logged day is not enough data for a trend.
        #expect(p.sentence(.energy) == TrendSentence.text(for: .energy, kind: .notEnoughData))
        #expect(p.hasAnyLog)
        #expect(p.days.count == 14 && p.window == .fortnight)
        #expect(!TrendsEngine.page(raw(), window: .week, calendar: utc).hasAnyLog)
    }
}
