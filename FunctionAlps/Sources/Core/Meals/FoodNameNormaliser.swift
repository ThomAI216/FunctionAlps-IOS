import Foundation

// The pricing ladder's normalisation key — a byte-for-byte port of `normalise()` in
// `supabase/functions/_shared/food-resolver.ts` (via the Expo `lib/nutrition/resolve/normalise.ts`).
//
// Tier 0a of the resolver looks a member's learned foods up by `normalise(rawName).core`. The APP writes those
// rows (`nb_patient_food_aliases.alias_norm`), so if the two normalisations disagree by one character the alias
// lands on a key nothing will ever read — a learning loop that looks like it works and teaches nothing.
enum FoodNameNormaliser {
    /// Words that describe how a food was PREPARED rather than what it is.
    private static let preparation: Set<String> = [
        "raw", "fresh", "frozen", "canned", "dried", "dry",
        "cooked", "uncooked", "boiled", "baked", "roasted", "roast", "grilled",
        "fried", "sauteed", "sautéed", "steamed", "poached", "braised", "toasted",
        "melted", "marinated", "smoked", "cured", "caramelized", "caramelised",
        "chopped", "sliced", "diced", "minced", "shredded", "grated", "crushed",
        "mixed", "whole", "halved", "peeled", "unpeeled",
        "homemade", "organic", "plain", "natural",
        "creamy", "crispy", "crunchy", "soft", "hard",
        "hot", "cold", "warm", "drizzle", "topping", "garnish",
        "cru", "crue", "cuit", "cuite", "frais", "fraiche", "fraîche",
        "grille", "grillee", "grillée", "grillé", "roti", "rotie", "rôti", "rôtie",
        "surgele", "surgelee", "surgelé", "surgelée", "maison", "nature",
    ]

    private static func singular(_ t: String) -> String {
        if t.count <= 3 { return t }
        if t.hasSuffix("ies") { return String(t.dropLast(3)) + "y" }
        if t.hasSuffix("oes") { return String(t.dropLast(2)) }
        if t.hasSuffix("ses") || t.hasSuffix("xes") || t.hasSuffix("zes") { return String(t.dropLast(2)) }
        if t.hasSuffix("s"), !t.hasSuffix("ss"), !t.hasSuffix("us") { return String(t.dropLast()) }
        return t
    }

    /// Lowercase, everything but letters / digits / spaces → space, collapse, trim (the JS `\p{L}\p{N}` classes).
    private static func clean(_ s: String) -> String {
        let mapped = s.lowercased().map { ($0.isLetter || $0.isNumber || $0 == " ") ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    private static func reduceTerm(_ raw: String) -> String {
        let cleaned = clean(raw)
        let kept = cleaned.split(separator: " ").map(String.init).filter { !$0.isEmpty && !preparation.contains($0) }.map(singular)
        if !kept.isEmpty { return kept.joined(separator: " ") }
        return cleaned.split(separator: " ").map { singular(String($0)) }.joined(separator: " ")
    }

    struct Normalised: Sendable, Equatable {
        /// The lookup key — the only thing tier 0a compares against.
        let core: String
        let alternatives: [String]
    }

    static func normalise(_ raw: String) -> Normalised {
        var alternatives: [String] = []
        var head = raw
        if let open = raw.firstIndex(of: "("), let close = raw[open...].firstIndex(of: ")"), open != raw.startIndex {
            head = String(raw[..<open])
            let gloss = reduceTerm(String(raw[raw.index(after: open)..<close]))
            if !gloss.isEmpty { alternatives.append(gloss) }
        }
        let parts = head.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let core = reduceTerm(parts.first ?? head)
        for p in parts.dropFirst() {
            let alt = reduceTerm(p)
            if !alt.isEmpty { alternatives.append(alt) }
        }
        let unstripped = clean(parts.first ?? head).split(separator: " ").map { singular(String($0)) }.joined(separator: " ")
        if !unstripped.isEmpty, unstripped != core { alternatives.append(unstripped) }
        return Normalised(core: core, alternatives: alternatives)
    }

    /// The exact value to store in `nb_patient_food_aliases.alias_norm`. Empty ⇒ do not write a row.
    static func aliasKey(_ rawName: String) -> String { normalise(rawName).core }
}

/// Which name did the PIPELINE produce, before the member fixed it? Keyed on names, never on position —
/// the Expo `correction-origins.ts`. Only the FIRST name and the LAST one matter, and only rows the pipeline
/// named may learn (a hand-added row being corrected must not be learned as if the model had said it).
final class CorrectionOrigins {
    struct Correction: Sendable, Equatable {
        let fromName: String
        let toName: String
        let grams: Double?
    }

    private var origins: [String: String] = [:]   // current name → the pipeline's first name for that row
    private var taken = Set<String>()
    private var seeded = false

    /// Record the pipeline's own names. Ignored after the first call.
    func seed(_ items: [MealItem]) {
        guard !seeded, !items.isEmpty else { return }
        seeded = true
        for it in items { origins[it.name] = it.name }
    }

    /// One rename, at any point in a chain of them.
    func rename(from: String, to: String) {
        guard from != to, let origin = origins[from] else { return }
        origins[from] = nil
        origins[to] = origin
    }

    /// Every in-place rename between two same-length lists.
    func recordRenames(before: [MealItem], after: [MealItem]) {
        guard before.count == after.count else { return }
        for (b, a) in zip(before, after) { rename(from: b.name, to: a.name) }
    }

    /// Corrections worth learning from the final list — each pair at most ONCE for this tracker's lifetime.
    func take(_ items: [MealItem]) -> [Correction] {
        var out: [Correction] = []
        for it in items {
            guard let origin = origins[it.name] else { continue }
            if FoodNameNormaliser.aliasKey(it.name).count < 2 { continue }
            if FoodNameNormaliser.aliasKey(origin) == FoodNameNormaliser.aliasKey(it.name) { continue }
            let id = "\(origin)→\(it.name)"
            if taken.contains(id) { continue }
            taken.insert(id)
            out.append(Correction(fromName: origin, toName: it.name, grams: it.estimatedGrams))
        }
        return out
    }
}
