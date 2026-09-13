import Foundation

/// The frx engine's `nb_user_patterns` rows, one honest sentence each — "we have seen that when you eat X, Y
/// follows". Pure templating over the engine's vocabulary; every claim in a sentence comes from the row
/// (n_obs, consistency, tier), nothing invented. Vocabulary the app cannot phrase truthfully degrades to nil.
struct UserPattern: Sendable, Equatable {
    var kind: String            // pattern | trigger_food
    var subject: String         // late_dinner | high_fat_dinner | large_dinner | high_fibre | high_glycemic | <food>
    var reaction: String        // next_energy | next_sleep | fullness | bloating | stool_quality
    var direction: String       // always "worse" — the engine only stores adverse relationships
    var effect: Double?
    var nObs: Int
    var consistency: Double?    // 0–1
    var tier: String            // confirmed (>=5 obs, >=70 % consistent) | hint
}

enum PatternText {
    private static func subjectPhrase(_ s: String) -> String? {
        switch s {
        case "late_dinner": String(localized: "pattern.subject.lateDinner", defaultValue: "you eat dinner late")
        case "high_fat_dinner": String(localized: "pattern.subject.highFatDinner", defaultValue: "dinner runs heavy on fats")
        case "large_dinner": String(localized: "pattern.subject.largeDinner", defaultValue: "dinner runs large")
        case "high_fibre": String(localized: "pattern.subject.highFibre", defaultValue: "you eat more fibre than usual")
        case "high_glycemic": String(localized: "pattern.subject.highGlycemic", defaultValue: "your meals run high-glycemic")
        default: nil
        }
    }

    private static func reactionPhrase(_ r: String) -> String? {
        switch r {
        case "next_energy": String(localized: "pattern.reaction.nextEnergy", defaultValue: "your next-morning energy tends to run lower")
        case "next_sleep": String(localized: "pattern.reaction.nextSleep", defaultValue: "your sleep that night tends to suffer")
        case "fullness": String(localized: "pattern.reaction.fullness", defaultValue: "you tend to feel uncomfortably full")
        case "bloating": String(localized: "pattern.reaction.bloating", defaultValue: "bloating tends to follow")
        case "stool_quality": String(localized: "pattern.reaction.stool", defaultValue: "your stool quality tends to dip")
        default: nil
        }
    }

    /// Which reaction keys speak to each score's explainer.
    static func reactions(for kind: MealScoreKind) -> [String] {
        switch kind {
        case .digestion: ["bloating", "fullness", "stool_quality"]
        case .glycemic: ["next_energy", "next_sleep"]
        case .inflammation: []
        }
    }

    private static func evidence(_ p: UserPattern) -> String {
        let times = String(localized: "pattern.seenTimes", defaultValue: "seen \(p.nObs) times")
        guard let c = p.consistency else { return times }
        return times + " " + String(localized: "pattern.consistent", defaultValue: "(\(Int((c * 100).rounded()))% consistent)")
    }

    /// One honest sentence per pattern row; nil for vocabulary we cannot phrase truthfully.
    static func sentence(_ p: UserPattern) -> String? {
        guard p.direction == "worse" else { return nil }
        let lead = p.tier == "confirmed"
            ? String(localized: "pattern.lead.confirmed", defaultValue: "We've seen that when")
            : String(localized: "pattern.lead.hint", defaultValue: "Early signal · when")
        if p.kind == "trigger_food" {
            guard let reaction = reactionPhrase("bloating") else { return nil }
            return String(localized: "pattern.sentence.food", defaultValue: "\(lead) \(p.subject) is on your plate, \(reaction) · \(evidence(p)).")
        }
        guard let subject = subjectPhrase(p.subject), let reaction = reactionPhrase(p.reaction) else { return nil }
        return String(localized: "pattern.sentence", defaultValue: "\(lead) \(subject), \(reaction) · \(evidence(p)).")
    }

    /// Confirmed before hints, then by consistency, then by observation count.
    static func rank(_ patterns: [UserPattern]) -> [UserPattern] {
        patterns.sorted { a, b in
            if a.tier != b.tier { return a.tier == "confirmed" }
            let ca = a.consistency ?? 0, cb = b.consistency ?? 0
            if ca != cb { return ca > cb }
            return a.nObs > b.nObs
        }
    }

    /// The patterns relevant to one score's explainer.
    static func forScore(_ patterns: [UserPattern], _ kind: MealScoreKind) -> [UserPattern] {
        let reactions = reactions(for: kind)
        return rank(patterns.filter { $0.kind == "trigger_food" ? kind == .digestion : reactions.contains($0.reaction) })
    }
}
