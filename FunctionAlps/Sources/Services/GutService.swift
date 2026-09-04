import Foundation

/// Everything the two gut screens need, and the one save (the Expo `saveGutCheckinV2`).
struct GutService: Sendable {
    static let historyDays = 14

    struct State: Sendable, Equatable {
        let day: String
        let today: GutTodayRead?
        let history: [GutDay]           // the previous days, oldest first (today excluded)
        let meals: [MealLog]            // last 14 days
        let reactions: [String: MealReaction]
    }

    private let backend: any FunctionAlpsBackend
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(backend: any FunctionAlpsBackend, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.calendar = calendar
        self.now = now
    }

    var today: String { ISO8601.dayString(now(), calendar: calendar) }

    func load(patientId: String) async throws -> State {
        let current = now()
        let day = today
        let since = calendar.date(byAdding: .day, value: -(Self.historyDays - 1), to: calendar.startOfDay(for: current)) ?? current
        async let todayRead = backend.gutToday(patientId: patientId, day: day)
        async let history = backend.gutHistory(patientId: patientId, since: ISO8601.dayString(since, calendar: calendar), before: day)
        async let meals = backend.meals(patientId: patientId, since: since)
        async let reactions = backend.mealReactions(patientId: patientId, since: since)
        return State(day: day, today: try await todayRead, history: (try? await history) ?? [], meals: (try? await meals) ?? [], reactions: (try? await reactions) ?? [:])
    }

    /// Nothing answered → nothing written (the Expo rule); otherwise the day upsert + one event per read.
    @discardableResult
    func save(patientId: String, answers: GutAnswerSet, notes: String?) async throws -> Bool {
        guard GutEngine.hasAnyAnswer(answers) else { return false }
        let at = now()
        let stool = GutEngine.dimensionOverall(.stool, answers[.stool] ?? .empty)
        let write = GutCheckinWrite(
            comfort: GutEngine.dimensionOverall(.comfort, answers[.comfort] ?? .empty), stool: stool,
            reactions: GutEngine.dimensionOverall(.reactions, answers[.reactions] ?? .empty), overall: GutEngine.overall(answers),
            answers: answers, notes: notes,
            stoolType: answers[.stool]?.specials.bristol, stoolQuality: GutEngine.to15(stool), stoolFrequency: answers[.stool]?.specials.frequency,
            completedAt: at
        )
        try await backend.upsertGutCheckin(patientId: patientId, day: today, write: write)
        try await backend.insertCheckinEvents(patientId: patientId, events: GutEngine.events(answers, at: at))
        return true
    }

    // MARK: Dashboard

    struct Dashboard: Sendable, Equatable {
        let score: Int?
        let factors: [GutEngine.Factor]
        let series: [Int?]              // 14 days, oldest first, today last
        let liked: [String]
        let disliked: [String]
        let todayReads: (comfort: Int?, stool: Int?, reactions: Int?)?
        static func == (a: Dashboard, b: Dashboard) -> Bool { a.score == b.score && a.series == b.series && a.liked == b.liked && a.disliked == b.disliked }
    }

    func dashboard(_ s: State) -> Dashboard {
        let reactionsByMeal = s.reactions
        func dayOf(_ meal: MealLog) -> String { ISO8601.dayString(meal.loggedAt, calendar: calendar) }
        let mealsByDay = Dictionary(grouping: s.meals, by: dayOf)
        // Current standing: per-field reach-back over history + today, reactions over every rated meal.
        let latest = GutEngine.latestEntry(today: s.today?.day, history: s.history)
        let allReactions = s.meals.compactMap { reactionsByMeal[$0.id] }
        let sig = GutEngine.signals(entry: latest, reactions: allReactions)
        let (score, factors) = GutEngine.gutScore(comfort: sig.comfort, reactions: sig.reactions, stool: sig.stool)
        // 14-day series.
        var series: [Int?] = []
        let byDay = Dictionary(uniqueKeysWithValues: s.history.map { ($0.day, $0) })
        for offset in stride(from: Self.historyDays - 1, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now())) ?? now()
            let key = ISO8601.dayString(date, calendar: calendar)
            let entry = key == s.day ? s.today?.day : byDay[key]
            let dayReactions = (mealsByDay[key] ?? []).compactMap { reactionsByMeal[$0.id] }
            let d = GutEngine.signals(entry: entry, reactions: dayReactions)
            series.append(GutEngine.gutScore(comfort: d.comfort, reactions: d.reactions, stool: d.stool).score)
        }
        let foods = GutEngine.foodCorrelations(meals: s.meals, reactions: reactionsByMeal)
        let todayReads = s.today.map { (comfort: $0.day.comfort, stool: $0.day.stool, reactions: $0.day.reactions) }
        return Dashboard(score: score, factors: factors, series: series, liked: foods.liked, disliked: foods.disliked, todayReads: todayReads)
    }
}
