import Foundation

/// The hub's per-signal numbers, pure: a 14-day series (oldest first, today last, missing days nil) and the
/// current value — today's row when there is one, otherwise nothing (an empty tile says "Log to see"; it
/// never shows yesterday as today). The Expo `rawMetricSeries` / `useGutScores` shape.
enum ScoresOverview {
    struct Signal: Sendable, Equatable {
        let score: Int?
        let series: [Int?]
    }

    /// The last `days` local calendar days ending today, as `YYYY-MM-DD`.
    static func dayKeys(days: Int = 14, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let today = calendar.startOfDay(for: now)
        return stride(from: days - 1, through: 0, by: -1).compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { ISO8601.dayString($0, calendar: calendar) }
        }
    }

    static func body(_ signal: BodySignal, checkins: [DailyCheckin], days: Int = 14, now: Date = Date(), calendar: Calendar = .current) -> Signal {
        let byDay = Dictionary(checkins.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let keys = dayKeys(days: days, now: now, calendar: calendar)
        let series = keys.map { byDay[$0].flatMap { signal.value(in: $0) } }
        return Signal(score: series.last ?? nil, series: series)
    }

    static func gut(_ signal: GutSignal, days gutDays: [GutDay], days: Int = 14, now: Date = Date(), calendar: Calendar = .current) -> Signal {
        let byDay = Dictionary(gutDays.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let keys = dayKeys(days: days, now: now, calendar: calendar)
        let series = keys.map { byDay[$0].flatMap { signal.value(in: $0) } }
        return Signal(score: series.last ?? nil, series: series)
    }

    /// The meal trio for the hub: 7-day average + trend from the logged meals (`ScoreHistory`).
    struct MealSummary: Sendable, Equatable {
        let avg: Int?
        let trend: ScoreHistory.Trend?
    }

    static func meal(_ kind: MealScoreKind, meals: [MealLog], now: Date = Date(), calendar: Calendar = .current) -> MealSummary {
        let history = ScoreHistory.build(meals, days: 14, now: now, calendar: calendar)
        return MealSummary(avg: ScoreHistory.recentAvg(history, kind), trend: ScoreHistory.trend(history, kind))
    }
}
