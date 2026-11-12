import Foundation

/// "Feeling for the day" (owner-validated 2026-11-12): how the member feels when the day starts — mood, felt energy and
/// motivation, 0–100 like every other slider, each with a short list of pills. One row per member per day
/// (`patient_day_feelings`). It is NOT a check-in moment: it never enters the day's mood or energy medians, which look
/// back on the day. Everything here is pure.
struct DayFeeling: Sendable, Equatable {
    /// `YYYY-MM-DD`.
    var day: String
    var mood: Int? = nil
    var energy: Int? = nil
    var motivation: Int? = nil
    /// Picked options by group (`DayFeelingSchema.groupKey`): only the group a slider's band asks.
    var pills: [String: [String]] = [:]
    /// The id of the end-screen rule shown (`MorningRule.id`).
    var endRule: String? = nil

    var hasAnswer: Bool { mood != nil || energy != nil || motivation != nil || pills.values.contains { !$0.isEmpty } }
}

/// The three sliders of the card and the pills each one asks.
enum DayFeelingSchema {
    enum Metric: String, CaseIterable, Sendable, Identifiable {
        case mood, energy, motivation
        var id: String { rawValue }
    }

    /// Which pill list a slider's value asks: low (< 40) "Why might it be low?", good (>= 60) "What helped?", else none.
    enum Ask: String, Sendable, Equatable {
        case why, helped
    }

    static let lowBelow = 40.0
    static let goodFrom = 60.0

    static func ask(for value: Double?) -> Ask? {
        guard let value else { return nil }
        if value < lowBelow { return .why }
        if value >= goodFrom { return .helped }
        return nil
    }

    /// The column key inside `patient_day_feelings.pills`.
    static func groupKey(_ metric: Metric, _ ask: Ask) -> String { metric.rawValue + "_" + ask.rawValue }

    static func slider(_ metric: Metric) -> SliderSpec {
        switch metric {
        case .mood:
            SliderSpec(key: "mood", label: String(localized: "feeling.mood", defaultValue: "Mood"),
                       lowLabel: String(localized: "feeling.mood.low", defaultValue: "Low"), highLabel: String(localized: "feeling.mood.high", defaultValue: "Bright"), words: words)
        case .energy:
            SliderSpec(key: "energy", label: String(localized: "feeling.energy", defaultValue: "Felt energy"),
                       lowLabel: String(localized: "feeling.energy.low", defaultValue: "Drained"), highLabel: String(localized: "feeling.energy.high", defaultValue: "Buzzing"), words: words)
        case .motivation:
            SliderSpec(key: "motivation", label: String(localized: "feeling.motivation", defaultValue: "Motivation"),
                       lowLabel: String(localized: "feeling.motivation.low", defaultValue: "None"), highLabel: String(localized: "feeling.motivation.high", defaultValue: "Driven"), words: words)
        }
    }

    /// Five words, low → high (shared by the three sliders).
    private static var words: [String] {
        [String(localized: "feeling.w.veryLow", defaultValue: "Very low"), String(localized: "feeling.w.low", defaultValue: "Low"),
         String(localized: "feeling.w.okay", defaultValue: "Okay"), String(localized: "feeling.w.good", defaultValue: "Good"),
         String(localized: "feeling.w.great", defaultValue: "Great")]
    }

    static func title(_ ask: Ask) -> String {
        switch ask {
        case .why: String(localized: "feeling.why", defaultValue: "Why might it be low?")
        case .helped: String(localized: "feeling.helped", defaultValue: "What helped?")
        }
    }

    private static func opt(_ key: String, _ label: String) -> PillOption { PillOption(key: key, label: label) }

    static func options(_ metric: Metric, _ ask: Ask) -> [PillOption] {
        switch (metric, ask) {
        case (.mood, .why): moodWhy
        case (.energy, .why): energyWhy
        case (.motivation, .why): motivationWhy
        case (_, .helped): helped
        }
    }

    static let moodWhy: [PillOption] = [
        opt("slept_badly", String(localized: "feeling.pill.slept_badly", defaultValue: "Slept badly")),
        opt("worried", String(localized: "feeling.pill.worried", defaultValue: "Worried")),
        opt("stressed_today", String(localized: "feeling.pill.stressed_today", defaultValue: "Stressed about today")),
        opt("sad", String(localized: "feeling.pill.sad", defaultValue: "Sad")),
        opt("irritable", String(localized: "feeling.pill.irritable", defaultValue: "Irritable")),
        opt("lonely", String(localized: "feeling.pill.lonely", defaultValue: "Lonely")),
    ]

    static let energyWhy: [PillOption] = [
        opt("poor_sleep", String(localized: "feeling.pill.poor_sleep", defaultValue: "Poor sleep")),
        opt("woke_tired", String(localized: "feeling.pill.woke_tired", defaultValue: "Woke up tired")),
        opt("hungry", String(localized: "feeling.pill.hungry", defaultValue: "Hungry")),
        opt("heavy_dinner", String(localized: "feeling.pill.heavy_dinner", defaultValue: "Heavy dinner")),
        opt("sore", String(localized: "feeling.pill.sore", defaultValue: "Sore")),
        opt("sick", String(localized: "feeling.pill.sick", defaultValue: "Sick")),
    ]

    static let motivationWhy: [PillOption] = [
        opt("nothing_to_look_forward_to", String(localized: "feeling.pill.nothing_to_look_forward_to", defaultValue: "Nothing to look forward to")),
        opt("overwhelmed", String(localized: "feeling.pill.overwhelmed", defaultValue: "Overwhelmed")),
        opt("bored", String(localized: "feeling.pill.bored", defaultValue: "Bored")),
        opt("tired", String(localized: "feeling.pill.tired", defaultValue: "Tired")),
        opt("unclear_priorities", String(localized: "feeling.pill.unclear_priorities", defaultValue: "Unclear priorities")),
    ]

    static let helped: [PillOption] = [
        opt("walk_before", String(localized: "feeling.pill.walk_before", defaultValue: "Went for a walk before this check-in")),
        opt("exercise", String(localized: "feeling.pill.exercise", defaultValue: "Exercise / training")),
        opt("morning_routine", String(localized: "feeling.pill.morning_routine", defaultValue: "Morning routine")),
        opt("got_daylight", String(localized: "feeling.pill.daylight", defaultValue: "Daylight")),
        opt("slept_well", String(localized: "feeling.pill.slept_well", defaultValue: "Slept well")),
        opt("breakfast", String(localized: "feeling.pill.breakfast", defaultValue: "Breakfast")),
        opt("meditation_breathwork", String(localized: "feeling.pill.meditation_breathwork", defaultValue: "Meditation / breathwork")),
        opt("cold_shower", String(localized: "feeling.pill.cold_shower", defaultValue: "Cold shower")),
        opt("time_with_someone", String(localized: "feeling.pill.time_with_someone", defaultValue: "Time with someone")),
    ]

    /// What is saved: only the pills of the group each slider's CURRENT value asks, and only options that exist for it. A
    /// slider moved from low to good must not keep its old "why" pills; a skipped slider keeps none.
    static func cleanedPills(_ pills: [String: [String]], mood: Double?, energy: Double?, motivation: Double?) -> [String: [String]] {
        var out: [String: [String]] = [:]
        let values: [(Metric, Double?)] = [(.mood, mood), (.energy, energy), (.motivation, motivation)]
        for (metric, value) in values {
            guard let ask = ask(for: value) else { continue }
            let key = groupKey(metric, ask)
            let valid = Set(options(metric, ask).map(\.key))
            let picked = (pills[key] ?? []).filter { valid.contains($0) }
            if !picked.isEmpty { out[key] = picked }
        }
        return out
    }
}
