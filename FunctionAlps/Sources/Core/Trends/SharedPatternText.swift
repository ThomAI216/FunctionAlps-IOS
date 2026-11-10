import Foundation

/// One clinician-validated pattern, ready to show: "Late dinner → Next-day energy" and the count it rests on.
struct SharedPattern: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let sentence: String
    /// `clinician_reviewed_at` — "Shared 8 Nov by your practitioner". Nil when the column is not readable.
    let sharedAt: Date?
}

/// Phrases a `nb_user_patterns` row as COUNTS from the member's own logs — "On 4 of 5 days with a late dinner,
/// your energy the next day was lower than on other days." — never as a diagnosis. RLS returns only rows a
/// practitioner has validated; this type only words them. `k` (the days it held) is derived from the row's
/// `consistency` over its `n_obs`; vocabulary the app cannot phrase truthfully degrades to nil (the row is left out),
/// exactly as `PatternText` does.
enum SharedPatternText {
    private struct Subject {
        let title: String
        let phrase: String
    }

    /// What the engine measured. `higherIsBetter`: a HIGHER value is the good side (energy, sleep, stool quality);
    /// the clause says which way the adverse (or favourable) direction moved.
    private enum Reaction {
        case nextEnergy, nextSleep, fullness, bloating, stoolQuality

        init?(_ raw: String) {
            switch raw {
            case "next_energy": self = .nextEnergy
            case "next_sleep": self = .nextSleep
            case "fullness": self = .fullness
            case "bloating": self = .bloating
            case "stool_quality": self = .stoolQuality
            default: return nil
            }
        }

        var title: String {
            switch self {
            case .nextEnergy: String(localized: "trends.pattern.reaction.nextEnergy", defaultValue: "Next-day energy")
            case .nextSleep: String(localized: "trends.pattern.reaction.nextSleep", defaultValue: "Sleep that night")
            case .fullness: String(localized: "trends.pattern.reaction.fullness", defaultValue: "Fullness")
            case .bloating: String(localized: "trends.pattern.reaction.bloating", defaultValue: "Bloating")
            case .stoolQuality: String(localized: "trends.pattern.reaction.stool", defaultValue: "Stool quality")
            }
        }

        /// The clause that ends the sentence, for the way the row's value moved against the other days.
        func clause(higher: Bool) -> String {
            switch (self, higher) {
            case (.nextEnergy, false): String(localized: "trends.pattern.clause.energy.lower", defaultValue: "your energy the next day was lower")
            case (.nextEnergy, true): String(localized: "trends.pattern.clause.energy.higher", defaultValue: "your energy the next day was higher")
            case (.nextSleep, false): String(localized: "trends.pattern.clause.sleep.lower", defaultValue: "your sleep that night was rated lower")
            case (.nextSleep, true): String(localized: "trends.pattern.clause.sleep.higher", defaultValue: "your sleep that night was rated higher")
            case (.fullness, true): String(localized: "trends.pattern.clause.fullness.higher", defaultValue: "you felt more full")
            case (.fullness, false): String(localized: "trends.pattern.clause.fullness.lower", defaultValue: "you felt less full")
            case (.bloating, true): String(localized: "trends.pattern.clause.bloating.higher", defaultValue: "your bloating was higher")
            case (.bloating, false): String(localized: "trends.pattern.clause.bloating.lower", defaultValue: "your bloating was lower")
            case (.stoolQuality, false): String(localized: "trends.pattern.clause.stool.lower", defaultValue: "your stool quality was lower")
            case (.stoolQuality, true): String(localized: "trends.pattern.clause.stool.higher", defaultValue: "your stool quality was higher")
            }
        }

        /// Does a HIGHER reading mean the good side?
        var higherIsBetter: Bool {
            switch self {
            case .nextEnergy, .nextSleep, .stoolQuality: true
            case .fullness, .bloating: false
            }
        }
    }

    private static func subject(_ p: UserPattern) -> Subject? {
        if p.kind == "trigger_food" {
            let name = p.subject.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return Subject(title: name.prefix(1).uppercased() + name.dropFirst(), phrase: name)
        }
        switch p.subject {
        case "late_dinner":
            return Subject(title: String(localized: "trends.pattern.subject.lateDinner", defaultValue: "Late dinner"),
                           phrase: String(localized: "trends.pattern.phrase.lateDinner", defaultValue: "a late dinner"))
        case "high_fat_dinner":
            return Subject(title: String(localized: "trends.pattern.subject.highFatDinner", defaultValue: "Fat-heavy dinner"),
                           phrase: String(localized: "trends.pattern.phrase.highFatDinner", defaultValue: "a fat-heavy dinner"))
        case "large_dinner":
            return Subject(title: String(localized: "trends.pattern.subject.largeDinner", defaultValue: "Large dinner"),
                           phrase: String(localized: "trends.pattern.phrase.largeDinner", defaultValue: "a large dinner"))
        case "high_fibre":
            return Subject(title: String(localized: "trends.pattern.subject.highFibre", defaultValue: "More fibre than usual"),
                           phrase: String(localized: "trends.pattern.phrase.highFibre", defaultValue: "more fibre than usual"))
        case "high_glycemic":
            return Subject(title: String(localized: "trends.pattern.subject.highGlycemic", defaultValue: "High-glycemic meals"),
                           phrase: String(localized: "trends.pattern.phrase.highGlycemic", defaultValue: "high-glycemic meals"))
        default:
            return nil
        }
    }

    /// k of n: `consistency` is the share of the `n_obs` observations in which the pattern held.
    static func counts(_ p: UserPattern) -> (k: Int, n: Int)? {
        guard p.nObs > 0, let consistency = p.consistency else { return nil }
        let n = p.nObs
        return (min(n, max(0, Int((Double(n) * consistency).rounded()))), n)
    }

    static func make(_ p: UserPattern) -> SharedPattern? {
        guard p.direction == "worse" || p.direction == "better", let (k, n) = counts(p), let subject = subject(p) else { return nil }
        // A shared food trigger is always about bloating, as `PatternText` already reads it.
        let reaction = Reaction(p.reaction) ?? (p.kind == "trigger_food" ? .bloating : nil)
        guard let reaction else { return nil }
        // "worse" moves a measure to its bad side: down for energy, sleep and stool quality; up for fullness and bloating.
        let higher = (p.direction == "worse") ? !reaction.higherIsBetter : reaction.higherIsBetter
        let title = String(localized: "trends.pattern.title", defaultValue: "\(subject.title) → \(reaction.title)")
        let sentence = String(localized: "trends.pattern.sentence",
                              defaultValue: "On \(k) of \(n) days with \(subject.phrase), \(reaction.clause(higher: higher)) than on other days.")
        return SharedPattern(id: "\(p.kind)|\(p.subject)|\(p.reaction)", title: title, sentence: sentence, sharedAt: p.reviewedAt)
    }
}
