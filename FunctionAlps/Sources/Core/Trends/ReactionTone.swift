import Foundation

/// How a meal reaction word reads, for the colour of its pill on the Trends and Digestion pages (owner request,
/// 2026-11-11): green = it sat well, orange = a bit off, red = real discomfort, grey = unknown. The colour is an
/// accent only — the word always stays on the pill (CLAUDE.md rule 10). Pure: classifies the stored KEY
/// (`felt_full`, `bloating`, …) or the English words; never the localised label.
enum ReactionTone: Sendable, Equatable {
    case positive, mild, strong, neutral

    private static let positiveKeys: Set<String> = [
        "sat well", "good", "felt good", "light", "energised", "energized", "felt light", "easy", "fine", "great",
        "comfortable", "felt okay", "okay",
    ]
    private static let mildKeys: Set<String> = [
        "a bit off", "watch", "a bit bloated", "felt full", "full", "overfull", "over full", "heavy", "felt heavy",
        "tired after", "tired", "mixed", "mixed reaction", "some bloating", "some gas", "sluggish",
    ]
    private static let strongKeys: Set<String> = [
        "bloated", "felt bloated", "bloating", "gas", "gassy", "felt gassy", "cramps", "cramping", "pain", "reflux",
        "nausea", "nauseous", "loose", "diarrhoea", "diarrhea", "rough", "bad", "vomiting",
    ]

    /// Lower-cased, with `_`/`-` read as spaces and runs of spaces collapsed.
    static func normalised(_ key: String) -> String {
        let spaced = key.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return spaced.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// The tone of one reaction key or English phrase. Unknown or empty → grey.
    static func tone(for key: String) -> ReactionTone {
        let k = normalised(key)
        if k.isEmpty { return .neutral }
        if strongKeys.contains(k) { return .strong }
        if mildKeys.contains(k) { return .mild }
        if positiveKeys.contains(k) { return .positive }
        // Not an exact match: a softened phrase ("a bit …", "some …", "slightly …") is mild before its word is read.
        if k.hasPrefix("a bit ") || k.hasPrefix("some ") || k.hasPrefix("slightly ") { return .mild }
        let words = Set(k.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: strongKeys) { return .strong }
        if !words.isDisjoint(with: mildKeys) { return .mild }
        if !words.isDisjoint(with: positiveKeys) { return .positive }
        return .neutral
    }

    /// The meal's own rating (7+ sat well · 4–6 a bit off · <4 rough).
    static func tone(for sentiment: MealReaction.Sentiment) -> ReactionTone {
        switch sentiment {
        case .good: .positive
        case .watch: .mild
        case .bad: .strong
        }
    }
}
