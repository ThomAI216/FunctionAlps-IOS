import Foundation

/// A follow-up question `preprocess-meal` asks about one extracted item (the Expo `Clarification`).
struct MealClarification: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable { case identity, quantity }

    var itemIndex: Int
    var question: String
    var options: [String]
    /// WHAT was asked, and therefore where the answer goes: an identity answer names the food, a quantity
    /// answer sets the portion and leaves the name alone. Without it, tapping "30 g" renamed the food to "30 g".
    var kind: Kind

    var id: String { "\(itemIndex)|\(question)" }
}

// What KIND of question the model just asked, and what to do with the answer — the Expo
// `lib/meal-log/clarification.ts`. `preprocess-meal` labels each clarification; the SHAPE of the options
// decides whenever the label is missing (an older deploy, or a roll where the model omitted the key).
enum ClarificationLogic {
    /// Mass only. Volumes are never converted here: "1 cup" is 185 g of rice and 240 g of milk, and only the
    /// model knows the food. It converts them and passes the familiar measure beside the grams.
    private static let massToGrams: [String: Double] = [
        "g": 1, "gr": 1, "gram": 1, "grams": 1, "gramme": 1, "grammes": 1,
        "kg": 1000, "kilo": 1000, "kilos": 1000, "kilogram": 1000, "kilogramme": 1000,
        "mg": 0.001,
    ]

    private static let mass: NSRegularExpression = {
        let units = massToGrams.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        return try! NSRegularExpression(pattern: #"(?:^|[\s(])(\d+(?:[.,]\d+)?)\s*("# + units + #")(?![a-zÀ-ſ])"#, options: [.caseInsensitive])
    }()

    /// Measure words in BOTH languages: the options are written in the member's app language.
    private static let measureWords: Set<String> = Set([
        "g", "gr", "gram", "grams", "kg", "mg", "ml", "cl", "dl", "l", "oz", "lb",
        "cup", "cups", "tbsp", "tsp", "tablespoon", "tablespoons", "teaspoon", "teaspoons",
        "bowl", "bowls", "glass", "glasses", "slice", "slices", "handful", "handfuls",
        "piece", "pieces", "portion", "portions", "serving", "servings", "plate", "plates",
        "scoop", "scoops", "square", "squares", "drizzle", "pinch",
        "gramme", "grammes", "kilo", "kilos", "litre", "litres",
        "tasse", "tasses", "cuillere", "cuilleres", "cuillère", "cuillères",
        "bol", "bols", "verre", "verres", "tranche", "tranches", "poignee", "poignée", "poignees", "poignées",
        "morceau", "morceaux", "part", "parts", "assiette", "assiettes",
        "carre", "carré", "carres", "carrés", "filet", "pincee", "pincée",
    ].map(ClarificationLogic.fold))

    /// A quantity option OPENS with a count: "1 slice" is a portion, "goat cheese slice" is a food.
    private static let leadsWithACount = try! NSRegularExpression(pattern: #"^\s*(?:\d|a\b|an\b|one\b|two\b|three\b|four\b|half\b|un\b|une\b|deux\b|trois\b|quatre\b|demi)"#, options: [.caseInsensitive])

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func hasMeasureWord(_ option: String) -> Bool {
        let tokens = fold(option).map { $0.isLetter || $0.isNumber || $0.isWhitespace ? $0 : " " }
        return String(tokens).split(separator: " ").contains { measureWords.contains(String($0)) }
    }

    /// Is this single option a PORTION rather than a food?
    static func looksLikeQuantity(_ option: String) -> Bool {
        guard !option.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return matches(leadsWithACount, option) && hasMeasureWord(option)
    }

    /// From the model's own label when it gave one; from the shape of the options when it did not.
    /// IDENTITY IS THE FALLBACK: a name the member can see and correct beats a silent number.
    static func classify(kind: String?, options: [String]) -> MealClarification.Kind {
        if kind == "quantity" { return .quantity }
        if kind == "identity" { return .identity }
        let usable = options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if usable.isEmpty { return .identity }
        return usable.allSatisfy(looksLikeQuantity) ? .quantity : .identity
    }

    struct QuantityAnswer: Sendable, Equatable {
        /// Absent when the option carries no MASS — the grams the model estimated stand.
        var estimatedG: Int?
        /// The familiar measure, when the option named one: "30 g (2 tbsp)" → "2 tbsp".
        var volumeMeasure: String?
        /// Exactly what the member tapped.
        var quantity: String
    }

    /// Read a tapped quantity option. Missing grams ⇒ `estimatedG` absent; a measure alone travels structured.
    static func parseQuantityAnswer(_ option: String) -> QuantityAnswer {
        let label = option.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = QuantityAnswer(quantity: label)
        let ns = label as NSString
        var hadMass = false
        if let m = mass.firstMatch(in: label, range: NSRange(location: 0, length: ns.length)) {
            hadMass = true
            let value = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "."))
            let factor = massToGrams[ns.substring(with: m.range(at: 2)).lowercased()]
            if let value, let factor, value > 0 {
                let grams = Int((value * factor).rounded())
                if grams > 0 { out.estimatedG = grams }
            }
        }
        if let open = label.firstIndex(of: "("), let close = label[open...].firstIndex(of: ")") {
            let inner = String(label[label.index(after: open)..<close])
            if hasMeasureWord(inner), !matches(mass, inner) {
                out.volumeMeasure = inner.trimmingCharacters(in: .whitespaces)
                return out
            }
        }
        if !hadMass, hasMeasureWord(label) { out.volumeMeasure = label }
        return out
    }

    /// Apply a tapped option to the item it was asked about.
    static func apply(_ answer: String, kind: MealClarification.Kind, to item: MealPreprocess.Item) -> MealPreprocess.Item {
        var out = item
        out.confidence = "high"
        if kind == .identity {
            out.name = answer
            return out
        }
        // THE NAME IS NEVER TOUCHED HERE. That single line was the bug.
        let parsed = parseQuantityAnswer(answer)
        out.quantity = parsed.quantity
        if let g = parsed.estimatedG { out.estimatedG = g }
        if let v = parsed.volumeMeasure { out.volumeMeasure = v }
        return out
    }

    // MARK: Repairing an option that came back in the wrong language (render-time only)

    private struct FrenchUnit { let one: String; let many: String; let article: String }

    private static let frenchUnits: [String: FrenchUnit] = [
        "tbsp": FrenchUnit(one: "c. à soupe", many: "c. à soupe", article: "une"),
        "tablespoon": FrenchUnit(one: "c. à soupe", many: "c. à soupe", article: "une"),
        "tablespoons": FrenchUnit(one: "c. à soupe", many: "c. à soupe", article: "une"),
        "tsp": FrenchUnit(one: "c. à café", many: "c. à café", article: "une"),
        "teaspoon": FrenchUnit(one: "c. à café", many: "c. à café", article: "une"),
        "teaspoons": FrenchUnit(one: "c. à café", many: "c. à café", article: "une"),
        "cup": FrenchUnit(one: "tasse", many: "tasses", article: "une"),
        "cups": FrenchUnit(one: "tasse", many: "tasses", article: "une"),
        "glass": FrenchUnit(one: "verre", many: "verres", article: "un"),
        "glasses": FrenchUnit(one: "verre", many: "verres", article: "un"),
        "bowl": FrenchUnit(one: "bol", many: "bols", article: "un"),
        "bowls": FrenchUnit(one: "bol", many: "bols", article: "un"),
        "slice": FrenchUnit(one: "tranche", many: "tranches", article: "une"),
        "slices": FrenchUnit(one: "tranche", many: "tranches", article: "une"),
        "handful": FrenchUnit(one: "poignée", many: "poignées", article: "une"),
        "handfuls": FrenchUnit(one: "poignée", many: "poignées", article: "une"),
        "piece": FrenchUnit(one: "morceau", many: "morceaux", article: "un"),
        "pieces": FrenchUnit(one: "morceau", many: "morceaux", article: "un"),
        "scoop": FrenchUnit(one: "boule", many: "boules", article: "une"),
        "scoops": FrenchUnit(one: "boule", many: "boules", article: "une"),
        "square": FrenchUnit(one: "carré", many: "carrés", article: "un"),
        "squares": FrenchUnit(one: "carré", many: "carrés", article: "un"),
        "pinch": FrenchUnit(one: "pincée", many: "pincées", article: "une"),
        "plate": FrenchUnit(one: "assiette", many: "assiettes", article: "une"),
        "plates": FrenchUnit(one: "assiette", many: "assiettes", article: "une"),
        "portion": FrenchUnit(one: "portion", many: "portions", article: "une"),
        "portions": FrenchUnit(one: "portion", many: "portions", article: "une"),
        "serving": FrenchUnit(one: "portion", many: "portions", article: "une"),
        "servings": FrenchUnit(one: "portion", many: "portions", article: "une"),
    ]
    private static let unitAlternation = frenchUnits.keys.sorted().joined(separator: "|")
    private static let halfA = try! NSRegularExpression(pattern: #"\bhalf (?:a|an) ("# + unitAlternation + #")\b"#, options: [.caseInsensitive])
    private static let counted = try! NSRegularExpression(pattern: #"\b(\d+(?:[.,]\d+)?)\s+("# + unitAlternation + #")\b"#, options: [.caseInsensitive])
    private static let articled = try! NSRegularExpression(pattern: #"\b(?:a|an) ("# + unitAlternation + #")\b"#, options: [.caseInsensitive])

    private static func replace(_ re: NSRegularExpression, in s: String, _ build: (NSTextCheckingResult, NSString) -> String) -> String {
        let ns = s as NSString
        var out = s
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            out = (out as NSString).replacingCharacters(in: m.range, with: build(m, ns))
        }
        return out
    }

    /// Rewrite the English measures inside a model-written option into French. Anything unrecognised is
    /// returned UNCHANGED. What gets STORED stays exactly as the model wrote it — this repairs what a member READS.
    static func localiseQuantityOption(_ option: String, locale: String) -> String {
        guard locale == "fr", !option.isEmpty else { return option }
        var s = replace(halfA, in: option) { m, ns in
            let u = frenchUnits[ns.substring(with: m.range(at: 1)).lowercased()]!
            return "\(u.article) demi-\(u.one)"
        }
        s = replace(counted, in: s) { m, ns in
            let n = ns.substring(with: m.range(at: 1))
            let u = frenchUnits[ns.substring(with: m.range(at: 2)).lowercased()]!
            let value = Double(n.replacingOccurrences(of: ",", with: ".")) ?? 1
            return "\(n) \(value > 1 ? u.many : u.one)"
        }
        s = replace(articled, in: s) { m, ns in
            let u = frenchUnits[ns.substring(with: m.range(at: 1)).lowercased()]!
            return "\(u.article) \(u.one)"
        }
        return s
    }
}
