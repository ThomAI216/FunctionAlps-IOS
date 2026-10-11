import Foundation

/// The answers a questionnaire page is judged against: this questionnaire's answers first, then the member's
/// earlier responses (the latest value wins), then the phone's own Apple Health state.
struct TrackAnswerContext: Sendable, Equatable {
    var current: [String: JSONValue] = [:]
    /// The member's OTHER responses (any status).
    var earlier: [TrackResponse] = []
    var healthConnected = false

    func value(_ key: String) -> JSONValue? {
        if let v = current[key], TrackLogic.isAnswered(v) { return v }
        return TrackLogic.latestAnswer(key, in: earlier)
    }
}

/// One page of a questionnaire = one `screen`, its questions in `position` order.
struct TrackPage: Sendable, Equatable, Identifiable {
    let screen: Int
    let questions: [TrackQuestion]
    var id: Int { screen }
}

/// The day's actions of one moment.
struct TrackActionGroup: Sendable, Equatable, Identifiable {
    let moment: TrackMoment
    let actions: [TrackAction]
    var id: String { moment.rawValue }
}

/// What the reminder planner needs to know about the track (nil = not on it, or past day 14).
struct TrackReminderPlan: Sendable, Equatable {
    /// The track day of today (device calendar ≈ Zurich).
    var today: Int
    var days: Int
    var pushes: [Int: [TrackMoment: TrackPush]]
    /// `HH:mm` answers (day 1 wake time, day 2 lunch time, day 4 bedtime); nil = the default.
    var wake: String?
    var lunch: String?
    var bedtime: String?
    var modulesDone: Int
    var modulesTotal: Int
    var mealsPct: Int?
    var reviewUnlocked: Bool
    var locale: String
}

/// The Foundation Track's rules, pure and tested. Nothing here computes a health figure: the server sends the
/// day, the modules, the meals and the ranges (rule 9); this file decides what to SHOW and how to word it.
enum TrackLogic {
    static let trackCode = "foundation_v1"

    // MARK: Language

    /// French when the app is drawn in French and the practice wrote it; English otherwise.
    static func text(_ en: String?, _ fr: String?, locale: String) -> String? { ActionCardLogic.pick(en, fr, locale: locale) }

    static func label(_ option: TrackOption, locale: String) -> String { text(option.labelEn, option.labelFr, locale: locale) ?? option.value }

    // MARK: Home card

    enum CardMode: Equatable {
        case hidden
        /// Days 1…14: the day's card.
        case today(day: Int)
        /// After the last day, until its questionnaire is submitted.
        case finished(questionnaireId: String?)
    }

    static func cardMode(status: TrackStatus?, questionnaires: [TrackQuestionnaire], submitted: Set<String>) -> CardMode {
        guard let status, status.state == .active, status.day >= 1 else { return .hidden }
        if status.day <= status.days { return .today(day: status.day) }
        let last = questionnaires.filter { $0.day == status.days }.first
        if let last, submitted.contains(last.id) { return .hidden }
        return .finished(questionnaireId: last?.id)
    }

    /// The questionnaires the card offers: today's, and every earlier one not submitted yet (oldest first).
    static func openQuestionnaires(_ questionnaires: [TrackQuestionnaire], today: Int, submitted: Set<String>) -> [TrackQuestionnaire] {
        questionnaires.filter { $0.day <= today && !submitted.contains($0.id) }.sorted { ($0.day, $0.id) < ($1.day, $1.id) }
    }

    /// The day's actions by moment, in the day's order (morning → midday → evening → during the day).
    static func grouped(_ actions: [TrackAction]) -> [TrackActionGroup] {
        TrackMoment.order.compactMap { moment in
            let rows = actions.filter { $0.moment == moment }
            return rows.isEmpty ? nil : TrackActionGroup(moment: moment, actions: rows)
        }
    }

    /// The practice's own title for the action; else the card's title for the action's face (`easy_title`,
    /// `rev_title`), else the card's title; else the key made readable.
    static func actionTitle(_ action: TrackAction, card: ActionCardRow?, locale: String) -> String {
        if let own = text(action.titleEn, action.titleFr, locale: locale) { return own }
        if let card {
            switch action.face {
            case "easy": if let t = text(card.easyTitle, card.easyTitleFr, locale: locale) { return t }
            case "further": if let t = text(card.revTitle, card.revTitleFr, locale: locale) { return t }
            default: break
            }
            return text(card.title, card.titleFr, locale: locale) ?? card.title
        }
        let words = action.key.replacingOccurrences(of: "_", with: " ")
        return String(words.prefix(1)).uppercased() + String(words.dropFirst())
    }

    /// The day card in the app's language: the whole French card when the app is drawn in French and the day has
    /// one, else the English card — and the other one when only that one exists (the rule `text` applies per field).
    static func card(_ day: TrackDay, locale: String) -> TrackDayCard? {
        locale == "fr" ? (day.cardFr ?? day.cardEn) : (day.cardEn ?? day.cardFr)
    }

    /// The infographic, https only, with what it shows for VoiceOver.
    static func infographic(_ day: TrackDay, locale: String) -> (url: URL, alt: String?)? {
        guard let raw = day.imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines), raw.lowercased().hasPrefix("https://"),
              let url = URL(string: raw) else { return nil }
        return (url, text(day.imageAltEn, day.imageAltFr, locale: locale))
    }

    /// The action card's version for a track action's face.
    static func habitFace(_ face: String) -> HabitFace {
        switch face {
        case "easy": return .easy
        case "further": return .progression
        default: return .standard
        }
    }

    static let bookingBase = "https://www.functionalps.ch/book/thomas/"

    /// Every track call is the 20-minute members call (Thomas, 2026-10-06: "Everything: 20 minutes"),
    /// so every call books `foundation-call-20`.
    static func bookingSlug(_ call: TrackCall) -> String { "foundation-call-20" }

    static func bookingURL(_ call: TrackCall) -> URL? { URL(string: bookingBase + bookingSlug(call)) }

    /// The calls to show: open ones only, one button per booking page (the latest day wins), so one button at most.
    static func openCalls(_ calls: [TrackCall]) -> [TrackCall] {
        var bySlug: [String: TrackCall] = [:]
        for call in calls where call.open {
            if let seen = bySlug[bookingSlug(call)], seen.day >= call.day { continue }
            bySlug[bookingSlug(call)] = call
        }
        return bySlug.values.sorted { $0.day < $1.day }
    }

    /// The "where you stand" row appears from day 7.
    static let progressFromDay = 7
    /// The day whose summary a practitioner approves (`track_summary.day`).
    static let summaryDay = 7

    /// `~2,250–2,450` — the server's two numbers, grouped the member's way.
    static func range(_ low: Int?, _ high: Int?, locale: Locale = .current) -> (String, String)? {
        guard let low, let high, low > 0, high >= low else { return nil }
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: low)) ?? "\(low)", f.string(from: NSNumber(value: high)) ?? "\(high)")
    }

    // MARK: Questionnaire — answers and conditions

    static func isAnswered(_ value: JSONValue) -> Bool {
        switch value {
        case .null: return false
        case .string(let s): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let a): return !a.isEmpty
        case .object(let o): return !o.isEmpty
        default: return true
        }
    }

    /// The latest answered value of `key` across responses (by `updated_at`).
    static func latestAnswer(_ key: String, in responses: [TrackResponse]) -> JSONValue? {
        let latest = responses
            .filter { $0.answers[key].map(isAnswered) ?? false }
            .max { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
        return latest?.answers[key]
    }

    /// Every clause present must hold. A key that has no answer yet fails its clause: a follow-up question
    /// appears once the question it follows is answered, not before.
    static func holds(_ condition: TrackCondition, in context: TrackAnswerContext) -> Bool {
        if let wanted = condition.healthConnected, wanted != context.healthConnected { return false }
        guard let key = condition.key else { return true }
        guard let value = context.value(key) else { return false }
        let texts = value.scalarTexts
        if let eq = condition.eq?.scalarText, !texts.contains(eq) { return false }
        if let list = condition.isIn {
            let set = Set(list.compactMap(\.scalarText))
            if !texts.contains(where: { set.contains($0) }) { return false }
        }
        if let list = condition.notIn {
            let set = Set(list.compactMap(\.scalarText))
            if texts.contains(where: { set.contains($0) }) { return false }
        }
        if let gte = condition.gte { guard let d = value.doubleValue, d >= gte else { return false } }
        if let lte = condition.lte { guard let d = value.doubleValue, d <= lte else { return false } }
        return true
    }

    /// Shown: a kind this build renders, and its `show_if` holds.
    static func isVisible(_ question: TrackQuestion, in context: TrackAnswerContext) -> Bool {
        guard question.kind != nil else { return false }
        return question.showIf.map { holds($0, in: context) } ?? true
    }

    /// Questions grouped by screen, screens and positions in order.
    static func pages(_ questions: [TrackQuestion]) -> [TrackPage] {
        Dictionary(grouping: questions, by: \.screen)
            .map { TrackPage(screen: $0.key, questions: $0.value.sorted { ($0.position, $0.key) < ($1.position, $1.key) }) }
            .sorted { $0.screen < $1.screen }
    }

    /// The pages to walk through: hidden questions left out, a page whose every question is hidden skipped.
    static func visiblePages(_ questions: [TrackQuestion], in context: TrackAnswerContext) -> [TrackPage] {
        pages(questions).compactMap { page in
            let shown = page.questions.filter { isVisible($0, in: context) }
            return shown.isEmpty ? nil : TrackPage(screen: page.screen, questions: shown)
        }
    }

    /// Continue is allowed when every visible required question on the page has an answer.
    static func canContinue(_ page: TrackPage, answers: [String: JSONValue]) -> Bool {
        page.questions.allSatisfy { q in
            guard q.required else { return true }
            switch q.kind {
            case .info?, .connectHealth?, .enableNotifications?, nil: return true
            default: return answers[q.key].map(isAnswered) ?? false
            }
        }
    }

    /// The answers as saved: keys of questions that are hidden now (a follow-up whose trigger changed) dropped,
    /// with their `_other` text.
    static func pruned(_ answers: [String: JSONValue], questions: [TrackQuestion], context: TrackAnswerContext) -> [String: JSONValue] {
        var out = answers
        for q in questions where !isVisible(q, in: context) {
            // A key asked twice in one questionnaire stays when any visible question owns it.
            if questions.contains(where: { $0.key == q.key && $0.id != q.id && isVisible($0, in: context) }) { continue }
            out[q.key] = nil
            out[q.key + "_other"] = nil
        }
        return out
    }

    // MARK: Prefill

    enum PrefillSource: Equatable { case answer, health }

    /// The value a question starts with: the member's latest earlier answer to the same key, or Apple Health's
    /// typical bedtime — only when it fits the question (an option that exists, a valid time).
    static func prefillValue(_ question: TrackQuestion, context: TrackAnswerContext, healthBedtime: String?) -> JSONValue? {
        switch question.prefill {
        case .answer(let key)?:
            guard key == question.key, let value = latestAnswer(key, in: context.earlier) else { return nil }
            return fits(value, question) ? value : nil
        case .health(let metric)?:
            guard metric == "bedtime", question.kind == .time, let bedtime = healthBedtime, minutes(bedtime) != nil else { return nil }
            return .string(bedtime)
        case .profile?, nil:
            return nil
        }
    }

    /// The small "from your earlier answers" / "from Apple Health" chip: shown while the value on screen is
    /// what was prefilled (or, for a question that only quotes an earlier answer, while that answer exists).
    static func prefillChip(_ question: TrackQuestion, context: TrackAnswerContext, healthBedtime: String?) -> PrefillSource? {
        switch question.prefill {
        case .answer(let key)?:
            guard let earlier = latestAnswer(key, in: context.earlier) else { return nil }
            if key != question.key { return .answer }
            return context.current[question.key] == earlier ? .answer : nil
        case .health?:
            guard let value = prefillValue(question, context: context, healthBedtime: healthBedtime) else { return nil }
            return context.current[question.key] == value ? .health : nil
        default:
            return nil
        }
    }

    static func fits(_ value: JSONValue, _ question: TrackQuestion) -> Bool {
        let optionValues: Set<String>? = {
            if case .list(let options)? = question.options { return Set(options.map(\.value)) }
            return nil
        }()
        switch question.kind {
        case .time?: return value.stringValue.flatMap { minutes($0) } != nil
        case .single?, .confirm?:
            guard let v = value.scalarText else { return false }
            return optionValues?.contains(v) ?? true
        case .multi?:
            guard case .array(let items) = value, !items.isEmpty else { return false }
            guard let optionValues else { return true }
            return items.compactMap(\.scalarText).allSatisfy { optionValues.contains($0) }
        case .number?, .slider?: return value.doubleValue != nil
        case .text?: return value.stringValue != nil
        default: return false
        }
    }

    // MARK: Prompts

    /// The first variant whose `when` holds, else the question's own prompt.
    static func rawPrompt(_ question: TrackQuestion, context: TrackAnswerContext, locale: String) -> String {
        for variant in question.variants where holds(variant.when, in: context) {
            return text(variant.promptEn, variant.promptFr, locale: locale) ?? variant.promptEn
        }
        return text(question.promptEn, question.promptFr, locale: locale) ?? question.promptEn
    }

    /// `{name}` → the resolver's text; a name it does not know becomes "…" (never a raw brace on screen).
    static func fill(_ template: String, _ resolve: (String) -> String?) -> String {
        guard template.contains("{") else { return template }
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out.append(contentsOf: rest[..<open])
            guard let close = rest[open...].firstIndex(of: "}") else { out.append(contentsOf: rest[open...]); rest = ""; break }
            let name = String(rest[rest.index(after: open)..<close])
            out += resolve(name) ?? "…"
            rest = rest[rest.index(after: close)...]
        }
        out.append(contentsOf: rest)
        return out
    }

    /// Every option list in the questionnaires, by question key — how an earlier answer is put back into words.
    static func optionIndex(_ questionnaires: [TrackQuestionnaire]) -> [String: [TrackOption]] {
        var out: [String: [TrackOption]] = [:]
        for q in questionnaires.flatMap(\.questions) {
            guard case .list(let options)? = q.options, out[q.key] == nil else { continue }
            out[q.key] = options
        }
        return out
    }

    /// An answer in words: option labels (a free-text option shows what the member wrote), joined.
    static func answerText(_ key: String, context: TrackAnswerContext, options: [String: [TrackOption]], locale: String) -> String? {
        guard let value = context.value(key) else { return nil }
        let list = options[key] ?? []
        let words: [String] = value.scalarTexts.map { v in
            guard let option = list.first(where: { $0.value == v }) else { return v }
            if option.freeText, let own = context.value(key + "_other")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty {
                return own
            }
            return label(option, locale: locale)
        }
        return words.isEmpty ? nil : words.joined(separator: ", ")
    }

    /// "{age} years · {height} cm · {weight} kg · {activity}" from the profile columns the question names.
    static func baselineLine(_ profile: MemberProfile?, fields: [String]) -> String? {
        guard let profile else { return nil }
        func number(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
        let parts: [String] = fields.compactMap { field -> String? in
            switch field {
            case "app_age": return profile.age.map { String(localized: "track.baseline.age", defaultValue: "\($0) years") }
            case "app_height_cm": return profile.heightCm.map { String(localized: "track.baseline.height", defaultValue: "\(number($0)) cm") }
            case "app_weight_kg": return profile.weightKg.map { String(localized: "track.baseline.weight", defaultValue: "\(number($0)) kg") }
            case "activity_level": return profile.activityLevel.flatMap(ActivityLevel.init(rawValue:))?.title
            default: return nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `{"source":"track_actions"}`: the distinct actions of days 1…min(day, 14), in the order they arrived.
    static func trackActionOptions(days: [TrackDay], through day: Int, cards: [String: ActionCardRow], locale: String) -> [TrackOption] {
        let last = min(max(day, 1), 14)
        var seen: Set<String> = []
        var out: [TrackOption] = []
        for d in days.sorted(by: { $0.day < $1.day }) where d.day <= last {
            for action in d.actions where seen.insert(action.key).inserted {
                out.append(TrackOption(value: action.key, labelEn: actionTitle(action, card: action.habitBankId.flatMap { cards[$0] }, locale: locale)))
            }
        }
        return out
    }

    /// The day-6 recap: a few plain sentences built from what the member said (fixed templates, no model).
    static func weekOneRecap(context: TrackAnswerContext, options: [String: [TrackOption]], locale: String) -> [String] {
        func words(_ key: String) -> String? { answerText(key, context: context, options: options, locale: locale) }
        func lower(_ key: String) -> String? { words(key).map { $0.lowercased() } }
        var out: [String] = []
        if let goals = words("primary_goals") { out.append(String(localized: "track.recap.goals", defaultValue: "What you'd like to improve: \(goals.lowercased()).")) }
        if let meals = lower("meals_per_day") { out.append(String(localized: "track.recap.meals", defaultValue: "You usually eat \(meals) meals a day.")) }
        if let lunch = words("lunch_time") { out.append(String(localized: "track.recap.lunch", defaultValue: "Lunch around \(lunch).")) }
        if let days = lower("exercise_days_week") { out.append(String(localized: "track.recap.exercise", defaultValue: "Exercise on purpose: \(days) days a week.")) }
        if let sitting = lower("sitting_hours_workday") { out.append(String(localized: "track.recap.sitting", defaultValue: "Sitting on a workday: \(sitting) hours.")) }
        if let latency = lower("sleep_latency") { out.append(String(localized: "track.recap.latency", defaultValue: "Falling asleep takes \(latency).")) }
        if let wakings = lower("night_wakings") { out.append(String(localized: "track.recap.wakings", defaultValue: "Waking in the night: \(wakings).")) }
        if let stress = words("stress_level") {
            if let sources = lower("stress_sources") {
                out.append(String(localized: "track.recap.stressSources", defaultValue: "Stress lately: \(stress)/10, mostly \(sources)."))
            } else {
                out.append(String(localized: "track.recap.stress", defaultValue: "Stress lately: \(stress)/10."))
            }
        }
        return out
    }

    // MARK: Time

    /// `HH:mm` → minutes after midnight; junk → nil.
    static func minutes(_ hhmm: String?) -> Int? {
        guard let hhmm, let p = NotificationPrefs.parse(hhmm) else { return nil }
        return p.hour * 60 + p.minute
    }

    static func hhmm(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// What a time question shows before the member moves the wheel — the times the reminder defaults assume.
    static func defaultTime(for key: String) -> String {
        if key.contains("lunch") { return defaultLunch }
        if key.contains("bed") { return defaultBedtime }
        if key.contains("wake") { return defaultWake }
        return "12:00"
    }

    static let defaultWake = "07:00"
    static let defaultLunch = "12:30"
    static let defaultBedtime = "22:15"

    /// Typical bedtime from Apple Health: the median start of the recent nights, to 5 minutes; nil with fewer
    /// than three nights. Starts after midnight count as late evenings.
    static func typicalBedtime(starts: [Date], calendar: Calendar = .current) -> String? {
        guard starts.count >= 3 else { return nil }
        let values = starts.map { d -> Int in
            let m = calendar.component(.hour, from: d) * 60 + calendar.component(.minute, from: d)
            return m < 12 * 60 ? m + 1440 : m
        }.sorted()
        let median = values.count % 2 == 1 ? values[values.count / 2] : (values[values.count / 2 - 1] + values[values.count / 2]) / 2
        return hhmm(Int((Double(median) / 5).rounded()) * 5)
    }

    // MARK: Reminders

    /// Minutes after the track day's midnight: morning = wake + 15, midday = lunch + 45, evening = bedtime − 45
    /// (defaults 07:15 · 13:15 · 21:30). A bedtime after midnight belongs to the evening before, so the
    /// evening value may pass 24:00.
    static func pushMinute(_ moment: TrackMoment, wake: String?, lunch: String?, bedtime: String?) -> Int? {
        switch moment {
        case .morning: return (minutes(wake) ?? 7 * 60) + 15
        case .midday: return (minutes(lunch) ?? 12 * 60 + 30) + 45
        case .evening:
            var bed = minutes(bedtime) ?? 22 * 60 + 15
            if bed < 12 * 60 { bed += 1440 }
            return bed - 45
        case .day: return nil
        }
    }

    /// Quiet hours: a morning or midday reminder waits for the window to end (the app's rule); an evening one
    /// comes 15 minutes BEFORE the window instead — tonight's reminder delivered tomorrow morning would be wrong.
    static func quietAdjusted(_ minute: Int, moment: TrackMoment, prefs: NotificationPrefs) -> Int {
        guard prefs.quietHoursEnabled, let start = minutes(prefs.quietStart), let end = minutes(prefs.quietEnd) else { return minute }
        let m = ((minute % 1440) + 1440) % 1440
        let base = minute - m
        let crosses = start > end
        let inside = crosses ? (m >= start || m < end) : (m >= start && m < end)
        guard inside else { return minute }
        if moment == .evening {
            return (crosses && m < end ? base - 1440 : base) + start - 15
        }
        return (crosses && m >= start ? base + 1440 : base) + end
    }

    static func pushApplies(_ push: TrackPush, reviewUnlocked: Bool) -> Bool {
        guard let condition = push.onlyIf else { return true }
        return condition == "review_unlocked" ? reviewUnlocked : false
    }

    /// The push text in the member's language, `{modules}` `{modules_total}` `{pct}` filled from the status.
    static func pushBody(_ push: TrackPush, plan: TrackReminderPlan) -> String {
        let raw = text(push.en, push.fr, locale: plan.locale) ?? push.en
        return fill(raw) { name -> String? in
            switch name {
            case "modules": return String(plan.modulesDone)
            case "modules_total": return String(plan.modulesTotal)
            case "pct": return String(plan.mealsPct ?? 0)
            default: return nil
            }
        }
    }

    /// The reminder plan while the member is on the track (active, day 1…days); nil otherwise.
    static func reminderPlan(status: TrackStatus?, days: [TrackDay], responses: [TrackResponse], locale: String) -> TrackReminderPlan? {
        guard let status, status.state == .active, (1...max(status.days, 1)).contains(status.day), !days.isEmpty else { return nil }
        func time(_ key: String) -> String? {
            latestAnswer(key, in: responses)?.stringValue.flatMap { minutes($0) != nil ? $0 : nil }
        }
        return TrackReminderPlan(
            today: status.day, days: status.days,
            pushes: Dictionary(days.map { ($0.day, $0.push) }, uniquingKeysWith: { first, _ in first }),
            wake: time("wake_time_workdays"), lunch: time("lunch_time"), bedtime: time("bedtime_workdays"),
            modulesDone: status.modulesDone, modulesTotal: status.modulesTotal, mealsPct: status.mealsPct,
            reviewUnlocked: status.reviewUnlocked, locale: locale
        )
    }
}
