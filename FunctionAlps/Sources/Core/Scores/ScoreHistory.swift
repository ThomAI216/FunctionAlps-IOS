import Foundation

/// Real per-score history from the logged meals (the Expo `score-history.ts`): scored meals bucketed by local
/// calendar day, each day's scores averaged, and from that the 7-day average + trend the explainer hero shows.
enum ScoreHistory {
    struct Day: Sendable, Equatable {
        let date: Date
        let inflammation: Int?
        let glycemic: Int?
        let digestion: Int?

        func value(_ kind: MealScoreKind) -> Int? {
            switch kind {
            case .inflammation: inflammation
            case .glycemic: glycemic
            case .digestion: digestion
            }
        }
    }

    enum Trend: Sendable, Equatable { case up, down, flat }

    /// The last `days` local calendar days (ending today), each with the per-score average of that day's scored
    /// meals, or nil when none were scored.
    static func build(_ meals: [MealLog], days: Int = 14, now: Date = Date(), calendar: Calendar = .current) -> [Day] {
        struct Acc { var n = 0; var i = 0; var g = 0; var d = 0 }
        var sums: [Date: Acc] = [:]
        for meal in meals {
            guard let s = meal.scores else { continue }
            let key = calendar.startOfDay(for: meal.loggedAt)
            var acc = sums[key] ?? Acc()
            acc.n += 1; acc.i += s.inflammation; acc.g += s.glycemic; acc.d += s.digestion
            sums[key] = acc
        }
        let today = calendar.startOfDay(for: now)
        return stride(from: days - 1, through: 0, by: -1).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let acc = sums[day]
            func avg(_ v: Int) -> Int? { acc.map { Int((Double(v) / Double($0.n)).rounded()) } }
            return Day(date: day, inflammation: acc.flatMap { avg($0.i) }, glycemic: acc.flatMap { avg($0.g) }, digestion: acc.flatMap { avg($0.d) })
        }
    }

    static func series(_ history: [Day], _ kind: MealScoreKind) -> [Int?] { history.map { $0.value(kind) } }

    /// Average over the days WITH data among the last `lastN` days; nil if none.
    static func recentAvg(_ history: [Day], _ kind: MealScoreKind, lastN: Int = 7) -> Int? {
        let vals = history.suffix(lastN).compactMap { $0.value(kind) }
        guard !vals.isEmpty else { return nil }
        return Int((Double(vals.reduce(0, +)) / Double(vals.count)).rounded())
    }

    /// Recent half vs prior half of the window; nil when either half is empty (not enough history to claim a
    /// direction). ±3 points is the flat band.
    static func trend(_ history: [Day], _ kind: MealScoreKind) -> Trend? {
        let half = history.count / 2
        let prior = history.prefix(half).compactMap { $0.value(kind) }
        let recent = history.dropFirst(half).compactMap { $0.value(kind) }
        guard !prior.isEmpty, !recent.isEmpty else { return nil }
        let p = Double(prior.reduce(0, +)) / Double(prior.count)
        let r = Double(recent.reduce(0, +)) / Double(recent.count)
        if r - p >= 3 { return .up }
        if p - r >= 3 { return .down }
        return .flat
    }

    /// True when at least `min` days in the window have data for the score.
    static func hasEnoughData(_ history: [Day], _ kind: MealScoreKind, min: Int = 2) -> Bool {
        history.filter { $0.value(kind) != nil }.count >= min
    }
}
