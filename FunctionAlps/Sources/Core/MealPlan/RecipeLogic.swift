import Foundation

/// The recipe card's pure rules: servings scaling, how an amount and an ingredient read, the Preparation | Cooking
/// split, and which "Make it…" versions are offered.
enum RecipeLogic {
    static let servingsRange = 1...12

    /// The stepper opens on the portions cooked for the slot, else the recipe's own servings, else 1.
    static func defaultServings(meal: PlannedMeal?, recipe: RecipeCard?) -> Int {
        let raw = meal?.servings ?? recipe?.servings ?? meal?.recipe.servings ?? 1
        return min(max(Int(raw.rounded()), servingsRange.lowerBound), servingsRange.upperBound)
    }

    /// An amount written for the whole recipe, scaled to the servings the member picked.
    static func scaled(_ qty: Double, recipeServings: Double?, chosen: Int) -> Double {
        let base = max(recipeServings ?? 1, 1)
        return qty * Double(chosen) / base
    }

    /// "½", "1½", "2", "2.5", "350". Grams and millilitres round to whole numbers from 10 up.
    static func amountText(_ value: Double, unit: String?, locale: Locale = .current) -> String {
        let measured = unit == "g" || unit == "ml" || unit == "mg"
        if measured {
            if value >= 10 { return GroceryLogic.number(value.rounded(), locale: locale, maxFraction: 0) }
            return GroceryLogic.number(value, locale: locale, maxFraction: 1)
        }
        let whole = value.rounded(.down)
        let fraction = value - whole
        let glyphs: [(Double, String)] = [(0.25, "¼"), (1.0 / 3.0, "⅓"), (0.5, "½"), (2.0 / 3.0, "⅔"), (0.75, "¾")]
        if fraction < 0.05 { return GroceryLogic.number(whole, locale: locale, maxFraction: 0) }
        if fraction > 0.95 { return GroceryLogic.number(whole + 1, locale: locale, maxFraction: 0) }
        if let glyph = glyphs.first(where: { abs($0.0 - fraction) < 0.04 }) {
            return whole > 0 ? "\(GroceryLogic.number(whole, locale: locale, maxFraction: 0))\(glyph.1)" : glyph.1
        }
        return GroceryLogic.number(value, locale: locale, maxFraction: 1)
    }

    static func unitText(_ code: String?) -> String {
        switch code {
        case nil, "": ""
        case "fl_oz": "fl oz"
        case let code?: code
        }
    }

    /// The amount column for one line at the chosen servings: "120 g", "2 tbsp", "½ lemon" style handled by the name.
    static func quantityLabel(_ line: RecipeIngredient, recipeServings: Double?, chosen: Int, locale: Locale = .current) -> String {
        if line.isToTaste { return String(localized: "recipe.toTaste", defaultValue: "to taste") }
        guard let qty = line.qty, qty > 0 else { return "" }
        let value = scaled(qty, recipeServings: recipeServings, chosen: chosen)
        let unit = unitText(line.unitCode)
        let amount = amountText(value, unit: line.unitCode, locale: locale)
        return unit.isEmpty ? amount : "\(amount) \(unit)"
    }

    private static let unitWords: Set<String> = [
        "g", "kg", "mg", "ml", "cl", "dl", "l", "oz", "lb", "tsp", "tbsp", "cup", "cups", "piece", "pieces", "clove", "cloves",
        "slice", "slices", "bunch", "bunches", "sprig", "sprigs", "leaf", "leaves", "stalk", "stalks", "handful", "tin", "tins",
        "can", "cans", "jar", "jars", "bottle", "bottles", "pack", "packs", "teaspoon", "teaspoons", "tablespoon", "tablespoons",
        "gram", "grams", "litre", "litres", "liter", "liters", "pinch",
    ]

    /// The line's food name. When the clinician typed the whole line ("200 g green lentils") and the amount is
    /// already in its own column, the leading amount and unit are dropped so it is not shown twice.
    static func ingredientName(_ line: RecipeIngredient) -> String {
        let raw = line.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.qty != nil, let first = raw.first, first.isNumber || "½¼¾⅓⅔".contains(first) else { return raw }
        var tokens = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count > 1 else { return raw }
        tokens.removeFirst()
        if let unit = tokens.first, tokens.count > 1, unitWords.contains(unit.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            tokens.removeFirst()
        }
        if tokens.first?.lowercased() == "of", tokens.count > 1 { tokens.removeFirst() }
        return tokens.joined(separator: " ")
    }

    // MARK: Method

    struct Method: Sendable, Equatable {
        var preparation: [String]
        var cooking: [String]

        var isEmpty: Bool { preparation.isEmpty && cooking.isEmpty }
        /// The segmented control shows only when both halves exist.
        var isSplit: Bool { !preparation.isEmpty && !cooking.isEmpty }
    }

    /// Preparation | Cooking. The recipe text may carry `## Preparation` and `## Cooking` headings; when it does the
    /// steps under each fall in their half. Otherwise the recipe's step list is the method, shown as one list.
    static func method(bodyMd: String, steps: [String]) -> Method {
        var prep: [String] = []
        var cook: [String] = []
        var current: Int?   // 0 prep, 1 cook, nil other
        var sawHeading = false
        for rawLine in bodyMd.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
                if title.contains("prepar") { current = 0; sawHeading = true }
                else if ["cook", "bake", "roast", "method", "direction", "instruction"].contains(where: title.contains) { current = 1; sawHeading = true }
                else { current = nil }
                continue
            }
            guard let section = current else { continue }
            let step = stripListMarker(line)
            if step.isEmpty { continue }
            if section == 0 { prep.append(step) } else { cook.append(step) }
        }
        if sawHeading, !(prep.isEmpty && cook.isEmpty) { return Method(preparation: prep, cooking: cook) }
        return Method(preparation: [], cooking: steps.map(stripListMarker).filter { !$0.isEmpty })
    }

    private static func stripListMarker(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("• ") { s = String(s.dropFirst(2)) }
        else if let dot = s.firstIndex(where: { $0 == "." || $0 == ")" }), dot > s.startIndex,
                s[s.startIndex..<dot].allSatisfy(\.isNumber), s.index(after: dot) < s.endIndex, s[s.index(after: dot)] == " " {
            s = String(s[s.index(dot, offsetBy: 2)...])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Make it…

    /// The approved versions that fit this member (the server already removed any that break their exclusions):
    /// candidates the server calls `variant`, not the one in force. When the meal is itself a version, the
    /// prescribed original is offered first so the member can go back.
    struct VersionOption: Sendable, Equatable, Identifiable {
        let recipeId: String
        let label: String
        var id: String { recipeId }
    }

    static func versions(candidates: [SwapCandidate], meal: PlannedMeal) -> [VersionOption] {
        var out: [VersionOption] = []
        if meal.swapped, meal.swapKind == "variant", let original = meal.prescribedId {
            out.append(VersionOption(recipeId: original, label: String(localized: "recipe.version.original", defaultValue: "Original")))
        }
        for c in candidates where c.source == .variant && !c.isCurrent && c.recipeId != meal.recipe.id {
            out.append(VersionOption(recipeId: c.recipeId, label: versionLabel(c.variantKind) ?? c.title))
        }
        return out
    }

    /// "higher_protein" → "Higher protein". A kind the app has no wording for is capitalised as written.
    static func versionLabel(_ kind: String?) -> String? {
        guard let kind = kind?.trimmingCharacters(in: .whitespacesAndNewlines), !kind.isEmpty else { return nil }
        let words = kind.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
