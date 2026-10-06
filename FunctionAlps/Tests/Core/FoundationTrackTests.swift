import Foundation
import Testing
@testable import FunctionAlps

@Suite("Foundation Track — questionnaire rules, the day's card and its reminders")
struct FoundationTrackTests {
    // MARK: Fixtures

    private func q(_ key: String, screen: Int, position: Int = 1, kind: TrackQuestionKind = .single, prompt: String = "?",
                   options: [String] = [], required: Bool = false, showIf: TrackCondition? = nil, prefill: TrackPrefill? = nil,
                   variants: [TrackVariant] = []) -> TrackQuestion {
        var question = TrackQuestion(id: key + "-\(screen)", key: key, screen: screen, kind: kind, promptEn: prompt)
        question.position = position
        if !options.isEmpty { question.options = .list(options.map { TrackOption(value: $0, labelEn: $0.capitalized) }) }
        question.required = required
        question.showIf = showIf
        question.prefill = prefill
        question.variants = variants
        return question
    }

    private func response(_ qid: String, _ answers: [String: JSONValue], updated: TimeInterval, submitted: Bool = true) -> TrackResponse {
        TrackResponse(id: "r-" + qid, questionnaireId: qid, answers: answers, submitted: submitted, submittedAt: nil,
                      updatedAt: Date(timeIntervalSince1970: updated))
    }

    private func condition(_ key: String, in values: [String]? = nil, notIn: [String]? = nil) -> TrackCondition {
        var c = TrackCondition()
        c.key = key
        c.isIn = values?.map(JSONValue.string)
        c.notIn = notIn?.map(JSONValue.string)
        return c
    }

    // MARK: show_if

    @Test("show_if: in / not_in against this questionnaire's answers, then earlier ones; unanswered hides a follow-up")
    func showIf() {
        let followUp = condition("recent_weight_change", in: ["down", "up"])
        #expect(!TrackLogic.holds(followUp, in: TrackAnswerContext()))                       // not answered yet → hidden
        #expect(TrackLogic.holds(followUp, in: TrackAnswerContext(current: ["recent_weight_change": .string("up")])))
        #expect(!TrackLogic.holds(followUp, in: TrackAnswerContext(current: ["recent_weight_change": .string("same")])))

        let notZero = condition("caffeine_per_day", notIn: ["0"])
        #expect(TrackLogic.holds(notZero, in: TrackAnswerContext(current: ["caffeine_per_day": .string("2")])))
        #expect(!TrackLogic.holds(notZero, in: TrackAnswerContext(current: ["caffeine_per_day": .string("0")])))

        // From an earlier module (day 3's answer read on a later day), and the current one wins over it.
        let earlier = [response("d3", ["exercise_days_week": .string("0")], updated: 100)]
        let zero = condition("exercise_days_week", in: ["0"])
        #expect(TrackLogic.holds(zero, in: TrackAnswerContext(earlier: earlier)))
        #expect(!TrackLogic.holds(zero, in: TrackAnswerContext(current: ["exercise_days_week": .string("3")], earlier: earlier)))

        // A multi answer matches when any chosen value is listed.
        let wakes = condition("waking_reasons", in: ["pain"])
        #expect(TrackLogic.holds(wakes, in: TrackAnswerContext(current: ["waking_reasons": .array([.string("bathroom"), .string("pain")])])))

        // Apple Health on this phone.
        var noHealth = TrackCondition()
        noHealth.healthConnected = false
        #expect(TrackLogic.holds(noHealth, in: TrackAnswerContext(healthConnected: false)))
        #expect(!TrackLogic.holds(noHealth, in: TrackAnswerContext(healthConnected: true)))

        // A kind this build does not know is never shown.
        var unknown = q("future", screen: 1)
        unknown = TrackQuestion(id: unknown.id, key: unknown.key, screen: 1, kind: nil, promptEn: "?")
        #expect(!TrackLogic.isVisible(unknown, in: TrackAnswerContext()))
    }

    // MARK: Pages

    @Test("Pages = screens in order, positions in order; a page whose every question is hidden is skipped")
    func pages() {
        let questions = [
            q("b", screen: 1, position: 2), q("a", screen: 1, position: 1),
            q("steps", screen: 2, showIf: { var c = TrackCondition(); c.healthConnected = false; return c }()),
            q("c", screen: 3), q("d", screen: 3, position: 2, showIf: condition("c", in: ["yes"])),
        ]
        let all = TrackLogic.pages(questions)
        #expect(all.map(\.screen) == [1, 2, 3])
        #expect(all[0].questions.map(\.key) == ["a", "b"])

        let connected = TrackLogic.visiblePages(questions, in: TrackAnswerContext(healthConnected: true))
        #expect(connected.map(\.screen) == [1, 3])                    // screen 2 only held the steps question
        #expect(connected[1].questions.map(\.key) == ["c"])           // d waits for c = yes
        let yes = TrackLogic.visiblePages(questions, in: TrackAnswerContext(current: ["c": .string("yes")], healthConnected: false))
        #expect(yes.map(\.screen) == [1, 2, 3])
        #expect(yes[2].questions.map(\.key) == ["c", "d"])
    }

    @Test("Required questions block Continue; info and permission pages never do; hidden answers are pruned")
    func continueAndPrune() {
        let page = TrackPage(screen: 1, questions: [q("goal", screen: 1, required: true), q("note", screen: 1, kind: .text), q("info", screen: 1, kind: .info, required: true)])
        #expect(!TrackLogic.canContinue(page, answers: [:]))
        #expect(!TrackLogic.canContinue(page, answers: ["goal": .string("  ")]))
        #expect(TrackLogic.canContinue(page, answers: ["goal": .string("energy")]))
        #expect(!TrackLogic.canContinue(TrackPage(screen: 1, questions: [q("m", screen: 1, kind: .multi, required: true)]), answers: ["m": .array([])]))

        let questions = [q("caffeine", screen: 1), q("last_coffee", screen: 1, showIf: condition("caffeine", notIn: ["0"]))]
        let answers: [String: JSONValue] = ["caffeine": .string("0"), "last_coffee": .string("after_17"), "last_coffee_other": .string("x")]
        let pruned = TrackLogic.pruned(answers, questions: questions, context: TrackAnswerContext(current: answers))
        #expect(pruned == ["caffeine": .string("0")])
    }

    // MARK: Prefill

    @Test("Prefill from an earlier answer: the latest value wins, only when it fits the question")
    func prefill() {
        let wake = q("wake_time_workdays", screen: 1, kind: .time, prefill: .answer(key: "wake_time_workdays"))
        let earlier = [
            response("d1", ["wake_time_workdays": .string("06:30")], updated: 100),
            response("d2", ["wake_time_workdays": .string("07:10")], updated: 200),
            response("d3", ["wake_time_workdays": .string("")], updated: 300),     // blank is not an answer
        ]
        let context = TrackAnswerContext(earlier: earlier)
        #expect(TrackLogic.prefillValue(wake, context: context, healthBedtime: nil) == .string("07:10"))
        #expect(TrackLogic.prefillChip(wake, context: TrackAnswerContext(current: ["wake_time_workdays": .string("07:10")], earlier: earlier), healthBedtime: nil) == .answer)
        #expect(TrackLogic.prefillChip(wake, context: TrackAnswerContext(current: ["wake_time_workdays": .string("08:00")], earlier: earlier), healthBedtime: nil) == nil)

        // A value that is not one of the options is not preselected.
        let single = q("diet_style", screen: 1, options: ["none", "vegan"], prefill: .answer(key: "diet_style"))
        #expect(TrackLogic.prefillValue(single, context: TrackAnswerContext(earlier: [response("x", ["diet_style": .string("paleo")], updated: 1)]), healthBedtime: nil) == nil)

        // A question that quotes another key (goals_confirm → primary_goals) shows the chip, preselects nothing.
        let confirm = q("goals_confirm", screen: 1, options: ["yes", "change"], prefill: .answer(key: "primary_goals"))
        let goals = TrackAnswerContext(earlier: [response("d1", ["primary_goals": .array([.string("energy")])], updated: 1)])
        #expect(TrackLogic.prefillValue(confirm, context: goals, healthBedtime: nil) == nil)
        #expect(TrackLogic.prefillChip(confirm, context: goals, healthBedtime: nil) == .answer)

        // Apple Health's typical bedtime, when there is one.
        let bed = q("bedtime_workdays", screen: 1, kind: .time, prefill: .health(metric: "bedtime"))
        #expect(TrackLogic.prefillValue(bed, context: TrackAnswerContext(), healthBedtime: "23:10") == .string("23:10"))
        #expect(TrackLogic.prefillValue(bed, context: TrackAnswerContext(), healthBedtime: nil) == nil)
    }

    @Test("Typical bedtime: the median start of at least three nights, after-midnight starts counted as late evening")
    func typicalBedtime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        func at(_ day: Int, _ h: Int, _ m: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))! }
        #expect(TrackLogic.typicalBedtime(starts: [at(1, 23, 0), at(2, 23, 20)], calendar: calendar) == nil)
        #expect(TrackLogic.typicalBedtime(starts: [at(1, 22, 50), at(3, 0, 40), at(2, 23, 12)], calendar: calendar) == "23:10")
    }

    // MARK: Prompts

    @Test("The first matching variant wins, else the prompt; placeholders are filled, unknown ones never show braces")
    func variants() {
        var when = TrackCondition()
        when.key = "exercise_days_week"
        when.isIn = [.string("4"), .string("5_plus")]
        let confidence = q("activity_confidence", screen: 1, kind: .slider, prompt: "Move a bit more?",
                           variants: [TrackVariant(when: when, promptEn: "Keep it up?", promptFr: "Continuer ?")])
        #expect(TrackLogic.rawPrompt(confidence, context: TrackAnswerContext(current: ["exercise_days_week": .string("2")]), locale: "en") == "Move a bit more?")
        #expect(TrackLogic.rawPrompt(confidence, context: TrackAnswerContext(current: ["exercise_days_week": .string("5_plus")]), locale: "en") == "Keep it up?")
        #expect(TrackLogic.rawPrompt(confidence, context: TrackAnswerContext(current: ["exercise_days_week": .string("4")]), locale: "fr") == "Continuer ?")

        #expect(TrackLogic.fill("On day 1 you chose: {primary_goals}. Still right?") { $0 == "primary_goals" ? "More energy, Better sleep" : nil }
                == "On day 1 you chose: More energy, Better sleep. Still right?")
        #expect(TrackLogic.fill("{nope} and {") { _ in nil } == "… and {")

        let options = ["primary_goals": [TrackOption(value: "energy", labelEn: "More energy", labelFr: "Plus d'énergie"),
                                         TrackOption(value: "other", labelEn: "Something else", freeText: true)]]
        let context = TrackAnswerContext(current: ["primary_goals": .array([.string("energy"), .string("other")]), "primary_goals_other": .string("Less pain")])
        #expect(TrackLogic.answerText("primary_goals", context: context, options: options, locale: "en") == "More energy, Less pain")
        #expect(TrackLogic.answerText("primary_goals", context: context, options: options, locale: "fr") == "Plus d'énergie, Less pain")
    }

    @Test("The baseline line uses only the fields the question names, and only those on file")
    func baseline() {
        let profile = MemberProfile(sex: .female, age: 41, heightCm: 168, weightKg: 62.5, activityLevel: "moderately_active", healthGoals: [], currentComplaints: [],
                                    dietaryPattern: nil, targetCalories: nil, targetProteinG: nil, targetCarbsG: nil, targetFatG: nil, goalMode: nil,
                                    onboardingCompletedAt: nil, locale: nil)
        let line = TrackLogic.baselineLine(profile, fields: ["app_age", "app_height_cm", "app_weight_kg", "activity_level"])
        #expect(line == "41 years · 168 cm · 62.5 kg · \(ActivityLevel.moderatelyActive.title)")
        #expect(TrackLogic.baselineLine(profile, fields: ["app_weight_kg"]) == "62.5 kg")
        #expect(TrackLogic.baselineLine(nil, fields: ["app_age"]) == nil)
    }

    // MARK: Actions

    @Test("Action titles: the practice's own title, else the card's title for the face, else the card's title")
    func actionTitles() {
        var card = ActionCardRow(id: "walk", title: "Walk after lunch")
        card.titleFr = "Marcher après le déjeuner"
        card.easyTitle = "5 minutes outside"
        card.revTitle = "A 20-minute walk"
        var action = TrackAction(key: "walk_after_lunch_5", moment: .midday, habitBankId: "walk", face: "easy")
        #expect(TrackLogic.actionTitle(action, card: card, locale: "en") == "5 minutes outside")
        action.face = "further"
        #expect(TrackLogic.actionTitle(action, card: card, locale: "en") == "A 20-minute walk")
        action.face = "standard"
        #expect(TrackLogic.actionTitle(action, card: card, locale: "fr") == "Marcher après le déjeuner")
        action.face = "easy"
        #expect(TrackLogic.actionTitle(action, card: card, locale: "fr") == "5 minutes outside")      // no French yet → English
        action.titleEn = "Lunch walk, 5 minutes"
        #expect(TrackLogic.actionTitle(action, card: card, locale: "en") == "Lunch walk, 5 minutes")
        #expect(TrackLogic.actionTitle(TrackAction(key: "meal_photos", moment: .day), card: nil, locale: "en") == "Meal photos")
        #expect(TrackLogic.habitFace("further") == .progression)
        #expect(TrackLogic.habitFace("easy") == .easy)
    }

    @Test("track_actions options: the distinct actions of days 1…min(day, 14), first title kept")
    func trackActionOptions() {
        let days = [
            TrackDay(day: 1, titleEn: "1", actions: [TrackAction(key: "meal_photos", moment: .day, titleEn: "Photograph every meal")]),
            TrackDay(day: 2, titleEn: "2", actions: [TrackAction(key: "meal_photos", moment: .day, titleEn: "Photograph every meal"),
                                                     TrackAction(key: "hydrate", moment: .morning, titleEn: "Hydrate")]),
            TrackDay(day: 3, titleEn: "3", actions: [TrackAction(key: "walk", moment: .midday, habitBankId: "c", face: "easy")]),
            TrackDay(day: 15, titleEn: "15", actions: [TrackAction(key: "never", moment: .day, titleEn: "Never")]),
        ]
        var card = ActionCardRow(id: "c", title: "Walk")
        card.easyTitle = "5 minutes outside"
        #expect(TrackLogic.trackActionOptions(days: days, through: 2, cards: [:], locale: "en").map(\.value) == ["meal_photos", "hydrate"])
        let all = TrackLogic.trackActionOptions(days: days, through: 30, cards: ["c": card], locale: "en")
        #expect(all.map(\.value) == ["meal_photos", "hydrate", "walk"])
        #expect(all.last?.labelEn == "5 minutes outside")
    }

    @Test("The card: today on days 1–14; after, 'done' until the last questionnaire is in; open questionnaires and calls")
    func card() {
        let qs = [TrackQuestionnaire(id: "d1", day: 1, titleEn: "You"), TrackQuestionnaire(id: "d2", day: 2, titleEn: "Eat"),
                  TrackQuestionnaire(id: "d14", day: 14, titleEn: "Two weeks")]
        var status = TrackStatus(state: .active, day: 3, days: 14)
        #expect(TrackLogic.cardMode(status: status, questionnaires: qs, submitted: []) == .today(day: 3))
        #expect(TrackLogic.cardMode(status: nil, questionnaires: qs, submitted: []) == .hidden)
        #expect(TrackLogic.cardMode(status: TrackStatus(state: .invited), questionnaires: qs, submitted: []) == .hidden)
        status.day = 16
        #expect(TrackLogic.cardMode(status: status, questionnaires: qs, submitted: []) == .finished(questionnaireId: "d14"))
        #expect(TrackLogic.cardMode(status: status, questionnaires: qs, submitted: ["d14"]) == .hidden)

        #expect(TrackLogic.openQuestionnaires(qs, today: 3, submitted: ["d2"]).map(\.id) == ["d1"])
        #expect(TrackLogic.openQuestionnaires(qs, today: 14, submitted: ["d1"]).map(\.id) == ["d2", "d14"])

        let calls = [TrackCall(day: 3, minutes: 20, gated: false, open: true), TrackCall(day: 7, minutes: 20, gated: false, open: true),
                     TrackCall(day: 14, minutes: 20, gated: true, open: false)]
        #expect(TrackLogic.openCalls(calls) == [TrackCall(day: 7, minutes: 20, gated: false, open: true)])
        // every call is the 20-minute members call: one booking page, so one button, the latest open day
        let review = [TrackCall(day: 3, minutes: 20, gated: false, open: true), TrackCall(day: 14, minutes: 20, gated: true, open: true)]
        #expect(TrackLogic.openCalls(review) == [TrackCall(day: 14, minutes: 20, gated: true, open: true)])
        #expect(TrackLogic.bookingURL(TrackCall(day: 3, minutes: 20, gated: false, open: true))?.absoluteString == "https://www.functionalps.ch/book/thomas/foundation-call-20")
        #expect(TrackLogic.bookingSlug(TrackCall(day: 14, minutes: 20, gated: true, open: true)) == "foundation-call-20")
        #expect(TrackLogic.bookingSlug(TrackCall(day: 3, minutes: 15, gated: false, open: true)) == "foundation-call-20") // an older row still books the members call

        let range = TrackLogic.range(2250, 2450, locale: Locale(identifier: "en_US"))
        #expect(range?.0 == "2,250" && range?.1 == "2,450")
        #expect(TrackLogic.range(nil, 2450) == nil)
    }

    // MARK: Reminders

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    @Test("Push times: wake + 15, lunch + 45, bedtime − 45, defaults 07:15 · 13:15 · 21:30; a bedtime after midnight")
    func pushTimes() {
        #expect(TrackLogic.pushMinute(.morning, wake: nil, lunch: nil, bedtime: nil).map(TrackLogic.hhmm) == "07:15")
        #expect(TrackLogic.pushMinute(.midday, wake: nil, lunch: nil, bedtime: nil).map(TrackLogic.hhmm) == "13:15")
        #expect(TrackLogic.pushMinute(.evening, wake: nil, lunch: nil, bedtime: nil).map(TrackLogic.hhmm) == "21:30")
        #expect(TrackLogic.pushMinute(.morning, wake: "06:40", lunch: nil, bedtime: nil).map(TrackLogic.hhmm) == "06:55")
        #expect(TrackLogic.pushMinute(.midday, wake: nil, lunch: "12:00", bedtime: nil).map(TrackLogic.hhmm) == "12:45")
        #expect(TrackLogic.pushMinute(.evening, wake: nil, lunch: nil, bedtime: "22:30") == 21 * 60 + 45)
        #expect(TrackLogic.pushMinute(.evening, wake: nil, lunch: nil, bedtime: "00:30") == 23 * 60 + 45)   // the same evening
        #expect(TrackLogic.pushMinute(.evening, wake: nil, lunch: nil, bedtime: "junk") == 21 * 60 + 30)
        #expect(TrackLogic.pushMinute(.day, wake: nil, lunch: nil, bedtime: nil) == nil)
    }

    @Test("Quiet hours: a morning reminder waits for the window's end; an evening one comes 15 minutes before it")
    func quietHours() {
        var prefs = NotificationPrefs.default            // 22:00–07:30
        #expect(TrackLogic.quietAdjusted(6 * 60 + 15, moment: .morning, prefs: prefs) == 7 * 60 + 30)
        #expect(TrackLogic.quietAdjusted(8 * 60, moment: .morning, prefs: prefs) == 8 * 60)
        #expect(TrackLogic.quietAdjusted(22 * 60 + 45, moment: .evening, prefs: prefs) == 21 * 60 + 45)
        #expect(TrackLogic.quietAdjusted(24 * 60 + 30, moment: .evening, prefs: prefs) == 21 * 60 + 45)    // 00:30 next day → 21:45 tonight
        #expect(TrackLogic.quietAdjusted(21 * 60 + 30, moment: .evening, prefs: prefs) == 21 * 60 + 30)
        prefs.quietHoursEnabled = false
        #expect(TrackLogic.quietAdjusted(22 * 60 + 45, moment: .evening, prefs: prefs) == 22 * 60 + 45)
    }

    private func plan(today: Int, unlocked: Bool = false, bedtime: String? = nil) -> TrackReminderPlan {
        TrackReminderPlan(
            today: today, days: 14,
            pushes: [
                1: [.evening: TrackPush(en: "First day done?")],
                2: [.morning: TrackPush(en: "Day 2 · water", fr: "Jour 2 · eau"), .midday: TrackPush(en: "Snap your lunch."),
                    .evening: TrackPush(en: "Where you stand: {modules}/{modules_total}, {pct}%.")],
                14: [.morning: TrackPush(en: "Day 14"), .evening: TrackPush(en: "Book your review.", onlyIf: "review_unlocked")],
            ],
            wake: "07:20", lunch: nil, bedtime: bedtime,
            modulesDone: 3, modulesTotal: 5, mealsPct: 82, reviewUnlocked: unlocked, locale: "en"
        )
    }

    @Test("The planner schedules the track's texts at the member's times; the evening one replaces the check-in reminder")
    func plannerSchedulesTrack() {
        var state = NotificationPlanner.State(now: date("2026-10-07 05:00"))       // track day 1 today
        state.track = plan(today: 1)
        let planned = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        let track = planned.filter { $0.id.hasPrefix("track.") }
        #expect(track.map(\.id) == ["track.evening.2026-10-07", "track.morning.2026-10-08", "track.midday.2026-10-08", "track.evening.2026-10-08"])
        #expect(track.first { $0.id == "track.morning.2026-10-08" }?.fireAt == date("2026-10-08 07:35"))
        #expect(track.first { $0.id == "track.midday.2026-10-08" }?.fireAt == date("2026-10-08 13:15"))
        #expect(track.first { $0.id == "track.evening.2026-10-08" }?.fireAt == date("2026-10-08 21:30"))
        #expect(track.first { $0.id == "track.evening.2026-10-08" }?.body == "Where you stand: 3/5, 82%.")
        #expect(track.allSatisfy { $0.route == "functionalps://foundation" })
        // Days with a track evening text: no check-in reminder; days without one keep it.
        #expect(!planned.contains { $0.id == "checkin.evening.2026-10-07" || $0.id == "checkin.evening.2026-10-08" })
        #expect(planned.contains { $0.id == "checkin.evening.2026-10-09" })
    }

    @Test("Day 14's review reminder only when the review is open; nothing after the last day; French when the app is")
    func plannerOnlyIfAndEnd() {
        var state = NotificationPlanner.State(now: date("2026-10-20 05:00"))
        state.track = plan(today: 14)
        var planned = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        #expect(planned.filter { $0.id.hasPrefix("track.") }.map(\.id) == ["track.morning.2026-10-20"])
        #expect(planned.contains { $0.id == "checkin.evening.2026-10-20" })        // no track evening → the check-in stays
        state.track = plan(today: 14, unlocked: true)
        planned = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar)
        #expect(planned.contains { $0.id == "track.evening.2026-10-20" })
        #expect(!planned.contains { $0.id == "checkin.evening.2026-10-20" })

        var french = plan(today: 2)
        french.locale = "fr"
        state = NotificationPlanner.State(now: date("2026-10-08 05:00"))
        state.track = french
        #expect(NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar).first { $0.id == "track.morning.2026-10-08" }?.body == "Jour 2 · eau")
    }

    @Test("A late bedtime: the evening text moves before quiet hours, on the same evening")
    func plannerQuietEvening() {
        var state = NotificationPlanner.State(now: date("2026-10-08 05:00"))
        state.track = plan(today: 2, bedtime: "23:30")
        let evening = NotificationPlanner.plan(prefs: .default, state: state, calendar: calendar).first { $0.id == "track.evening.2026-10-08" }
        #expect(evening?.fireAt == date("2026-10-08 21:45"))
        let quieted = NotificationPlanner.respectingQuietHours(evening.map { [$0] } ?? [], prefs: .default, calendar: calendar)
        #expect(quieted.first?.fireAt == date("2026-10-08 21:45"))
    }

    @Test("The reminder plan exists only while active on days 1…14, with the member's own times")
    func reminderPlan() {
        let days = [TrackDay(day: 1, titleEn: "1", push: [.evening: TrackPush(en: "x")])]
        let answers = [response("d1", ["wake_time_workdays": .string("06:30")], updated: 1), response("d2", ["lunch_time": .string("12:15")], updated: 2)]
        let active = TrackStatus(state: .active, day: 3, days: 14, modulesDone: 2, modulesTotal: 5)
        let p = TrackLogic.reminderPlan(status: active, days: days, responses: answers, locale: "en")
        #expect(p?.wake == "06:30" && p?.lunch == "12:15" && p?.bedtime == nil)
        #expect(p?.modulesDone == 2)
        #expect(TrackLogic.reminderPlan(status: TrackStatus(state: .active, day: 15, days: 14), days: days, responses: [], locale: "en") == nil)
        #expect(TrackLogic.reminderPlan(status: TrackStatus(state: .invited), days: days, responses: [], locale: "en") == nil)
        #expect(TrackLogic.reminderPlan(status: nil, days: days, responses: [], locale: "en") == nil)
    }

    // MARK: Wire shapes (the seed's jsonb, keys verbatim)

    @Test("Rows decode with their keys verbatim: answers, actions, push, options, show_if, prefill, variants, status")
    func decoding() throws {
        let day = Data("""
        [{"day": 9, "title_en": "A lunch that holds you", "title_fr": null, "questionnaire_id": null, "video_url_en": null,
          "actions": [{"key": "walk_after_lunch_10", "moment": "midday", "face": "standard", "new": true, "habit_bank_id": "7e6e"},
                      {"key": "coffee_before_14", "moment": "midday", "face": "standard", "new": false, "title_en": "Last coffee before 14:00"},
                      {"moment": "midday"}],
          "push": {"morning": {"en": "Day 9 · lunch"}, "evening": {"en": "Book.", "only_if": "review_unlocked"}, "bogus": {"en": "x"}}}]
        """.utf8)
        let d = try TrackJSON.decode([TrackDayWire].self, from: day)[0].day
        #expect(d.actions.map(\.key) == ["walk_after_lunch_10", "coffee_before_14"])
        #expect(d.actions[0].isNew && d.actions[0].habitBankId == "7e6e")
        #expect(d.push[.evening]?.onlyIf == "review_unlocked")
        #expect(d.push.count == 2)

        let question = Data("""
        [{"id": "q1", "questionnaire_id": "d1", "question_key": "primary_goals", "screen": 2, "position": 1, "kind": "multi",
          "prompt_en": "Pick up to 3.", "options": [{"value": "energy", "label_en": "More energy"}, {"value": "other", "label_en": "Something else", "free_text": true}],
          "max_select": 3, "min_value": null, "required": true, "voice": false,
          "show_if": {"key": "goals_confirm", "in": ["change"]}, "prefill": {"from": "profile", "fields": ["app_age", "app_weight_kg"]},
          "variants": [{"when": {"health_connected": false}, "prompt_en": "Other"}]},
         {"id": "q2", "questionnaire_id": "d14", "question_key": "actions_hard", "screen": 2, "kind": "multi", "prompt_en": "Hard?",
          "options": {"source": "track_actions"}, "step": 0.5, "min_value": "0"}]
        """.utf8)
        let qs = try TrackJSON.decode([TrackQuestionWire].self, from: question).map(\.question)
        #expect(qs[0].kind == .multi && qs[0].maxSelect == 3 && qs[0].required)
        if case .list(let options)? = qs[0].options { #expect(options.last?.freeText == true) } else { Issue.record("options") }
        #expect(qs[0].showIf?.isIn == [.string("change")])
        #expect(qs[0].prefill == .profile(fields: ["app_age", "app_weight_kg"]))
        #expect(qs[0].variants.first?.when.healthConnected == false)
        #expect(qs[1].options == .trackActions && qs[1].step == 0.5 && qs[1].minValue == 0)

        let responses = Data("""
        [{"id": "r1", "questionnaire_id": "d1", "status": "in_progress", "submitted_at": null, "updated_at": "2026-10-06T12:00:00.123456+00:00",
          "answers": {"success_3_months": "More energy", "recent_weight_change_kg": 2.5, "primary_goals": ["energy", "sleep"], "meals_per_day": "4_plus"}}]
        """.utf8)
        let r = try TrackJSON.decode([TrackResponseWire].self, from: responses)[0].response
        #expect(r.answers["success_3_months"] == .string("More energy"))
        #expect(r.answers["recent_weight_change_kg"] == .number(2.5))
        #expect(r.answers["primary_goals"] == .array([.string("energy"), .string("sleep")]))
        #expect(!r.submitted && r.updatedAt != nil)

        let status = Data("""
        {"track_code": "foundation_v1", "status": "active", "day": 7, "days": 14, "modules_done": 4, "modules_total": 5,
         "meals_expected": 21, "meals_logged": 17, "meals_pct": 81, "review_unlocked": false,
         "calls": [{"day": 3, "minutes": 20, "gated": false, "open": true}, {"day": 14, "minutes": 20, "gated": true, "open": false}],
         "energy_kcal_low": 2250, "energy_kcal_high": 2450.0, "protein_g_low": null}
        """.utf8)
        let s = try #require(try TrackJSON.decode(TrackStatusWire.self, from: status).status)
        #expect(s.state == .active && s.day == 7 && s.mealsPct == 81 && s.energyKcalHigh == 2450 && s.proteinGLow == nil)
        #expect(s.calls == [TrackCall(day: 3, minutes: 20, gated: false, open: true), TrackCall(day: 14, minutes: 20, gated: true, open: false)])
        #expect(try TrackJSON.decode(TrackStatusWire.self, from: Data(#"{"track_code":"foundation_v1","status":"invited"}"#.utf8)).status?.state == .invited)
    }
}
