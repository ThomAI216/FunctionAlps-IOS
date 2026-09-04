import Foundation

/// Gut scoring — the Expo `gut-engine.ts` (the form's per-dimension reads) and `lib/health/gut-breakdown.ts`
/// + `gut-signals.ts` + `score-core.ts` (the dashboard score). Pure and tested.
enum GutEngine {
    private static func jsRound(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }
    private static func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

    static func availableCaseMean(_ vals: [Double?]) -> Int? {
        let present = vals.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return jsRound(present.reduce(0, +) / Double(present.count))
    }

    // MARK: The form (gut-engine.ts)

    /// Bristol 3–4 → 100; 1 → 0, 2 → 50; 5 → 67, 6 → 33, 7 → 0.
    static func bristolScore(_ t: Int?) -> Double? {
        guard let t else { return nil }
        if t >= 3 && t <= 4 { return 100 }
        if t < 3 { return Double(jsRound((1 - clamp01(Double(3 - t) / 2)) * 100)) }
        return Double(jsRound((1 - clamp01(Double(t - 4) / 3)) * 100))
    }

    /// 1–3 stools → 100; 0 → 40; 4–5 → 70; more → 0.
    static func freqScore(_ n: Int?) -> Double? {
        guard let n else { return nil }
        if n >= 1 && n <= 3 { return 100 }
        if n == 0 { return 40 }
        if n <= 5 { return 70 }
        return 0
    }

    static func stoolScore(_ a: GutAnswers) -> Int? {
        availableCaseMean([bristolScore(a.specials.bristol), freqScore(a.specials.frequency), a.sliders["ease"]])
    }

    static func dimensionOverall(_ key: GutDimKey, _ a: GutAnswers) -> Int? {
        switch key {
        case .comfort: a.sliders["comfort"].map(jsRound)
        case .stool: stoolScore(a)
        case .reactions: a.specials.reactionsScore ?? a.sliders["reactions"].map(jsRound)
        }
    }

    static func overall(_ answers: GutAnswerSet) -> Int? {
        availableCaseMean(GutDimKey.order.map { dimensionOverall($0, answers[$0] ?? .empty).map(Double.init) })
    }

    /// 0–100 → the legacy 1–5 `stool_quality` column.
    static func to15(_ v: Int?) -> Int? {
        guard let v else { return nil }
        return max(1, min(5, jsRound(Double(v) / 20)))
    }

    /// One `nb_checkin_events` row per answered dimension.
    static func events(_ answers: GutAnswerSet, at: Date) -> [CheckinEvent] {
        GutDimKey.order.compactMap { key in dimensionOverall(key, answers[key] ?? .empty).map { CheckinEvent(dimension: key.rawValue, value: $0, ts: at) } }
    }

    static func hasAnyAnswer(_ answers: GutAnswerSet) -> Bool { overall(answers) != nil }

    // MARK: The dashboard (gut-breakdown.ts · gut-signals.ts · marker-trends.ts)

    struct Factor: Sendable, Equatable, Identifiable {
        let key: String
        let label: String
        let value: Int?
        let weight: Double
        var id: String { key }
        /// null → watch · ≥ 67 good · ≥ 34 watch · else bad.
        var status: String {
            guard let value else { return "watch" }
            return value >= 67 ? "good" : value >= 34 ? "watch" : "bad"
        }
    }

    /// Available-case weighted mean with weight renormalisation; nil when nothing is present.
    static func weightedScore(_ factors: [Factor]) -> Int? {
        let present = factors.filter { $0.value != nil }
        guard !present.isEmpty else { return nil }
        let total = present.reduce(0) { $0 + $1.weight }
        return jsRound(present.reduce(0) { $0 + Double($1.value!) * $1.weight } / total)
    }

    static func gutScore(comfort: Int?, reactions: Int?, stool: Int?) -> (score: Int?, factors: [Factor]) {
        let factors = [
            Factor(key: "comfort", label: String(localized: "gut.factor.comfort", defaultValue: "Digestion comfort"), value: comfort, weight: 0.4),
            Factor(key: "reactions", label: String(localized: "gut.factor.reactions", defaultValue: "Post-meal reactions"), value: reactions, weight: 0.3),
            Factor(key: "stool", label: String(localized: "gut.factor.stool", defaultValue: "Stool quality"), value: stool, weight: 0.3),
        ]
        return (weightedScore(factors), factors)
    }

    /// Per meal: clamp(overall × 10 − mean(bloating, gas, fullness) × 3); the mean over meals with a rating.
    static func mealReactionsScore(_ reactions: [MealReaction]) -> Int? {
        let scores: [Double] = reactions.compactMap { r in
            guard let overall = r.overall else { return nil }
            let symptoms = [r.bloating, r.gas, r.fullness].compactMap { $0 }
            let burden = symptoms.isEmpty ? 0 : symptoms.reduce(0, +) / Double(symptoms.count)
            return max(0, min(100, overall * 10 - burden * 3))
        }
        guard !scores.isEmpty else { return nil }
        return jsRound(scores.reduce(0, +) / Double(scores.count))
    }

    /// Legacy `stool_quality` 1–5 → 0–100.
    static func stoolQualityScore(_ v: Int?) -> Double? { v.map { Double(jsRound(clamp01(Double($0 - 1) / 4) * 100)) } }
    /// Legacy `stool_frequency` → 0–100 (1–3 → 100, 0 → 40, 4–5 → 70, more → 0).
    static func stoolFrequencyScore(_ v: Int?) -> Double? {
        guard let v else { return nil }
        let badness: Double = (1...3).contains(v) ? 0 : v == 0 ? 0.6 : v <= 5 ? 0.3 : 1
        return Double(jsRound((1 - badness) * 100))
    }

    /// The three inputs for one day: comfort has no fallback; stool falls back to the legacy markers.
    static func signals(entry: GutDay?, reactions: [MealReaction]) -> (comfort: Int?, stool: Int?, reactions: Int?) {
        let stool = entry?.stool ?? availableCaseMean([stoolQualityScore(entry?.stoolQuality), stoolFrequencyScore(entry?.stoolFrequency)])
        return (entry?.comfort, stool, mealReactionsScore(reactions))
    }

    /// Per-field most-recent-non-null reach-back across the history (oldest first) and today.
    static func latestEntry(today: GutDay?, history: [GutDay]) -> GutDay? {
        let all = history + (today.map { [$0] } ?? [])
        guard let last = all.last else { return nil }
        func latest<T>(_ f: (GutDay) -> T?) -> T? {
            for e in all.reversed() { if let v = f(e) { return v } }
            return nil
        }
        return GutDay(day: last.day, comfort: latest(\.comfort), stool: latest(\.stool), reactions: latest(\.reactions), overall: latest(\.overall), stoolQuality: latest(\.stoolQuality), stoolFrequency: latest(\.stoolFrequency), completedAt: last.completedAt)
    }

    enum Status: Sendable { case onTrack, needsSupport, watchClosely }
    /// ≥ 75 on track · ≥ 55 needs support · else watch closely.
    static func status(_ score: Int) -> Status { score >= 75 ? .onTrack : score >= 55 ? .needsSupport : .watchClosely }

    /// Foods from rated meals: sat well (overall ≥ 7) vs didn't (overall ≤ 4), top 6 each by count.
    static func foodCorrelations(meals: [MealLog], reactions: [String: MealReaction]) -> (liked: [String], disliked: [String]) {
        var good: [String: Int] = [:], bad: [String: Int] = [:]
        for meal in meals {
            guard let overall = reactions[meal.id]?.overall else { continue }
            for item in meal.items {
                let name = item.name.trimmingCharacters(in: .whitespaces).lowercased()
                guard !name.isEmpty else { continue }
                if overall >= 7 { good[name, default: 0] += 1 } else if overall <= 4 { bad[name, default: 0] += 1 }
            }
        }
        func top(_ m: [String: Int]) -> [String] { m.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(6).map { $0.key.capitalized } }
        return (top(good), top(bad))
    }
}
