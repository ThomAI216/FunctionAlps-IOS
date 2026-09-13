import Foundation

/// The working copy of an analysed meal while the member corrects it (the Expo `MealAnalysis`).
/// Nil until real numbers exist: a draft is never synthesised from zeros.
struct MealDraft: Sendable, Equatable {
    struct Totals: Sendable, Equatable {
        var kcal: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double
        var fiberG: Double
    }

    var dishName: String
    var items: [MealItem]
    var totals: Totals
    var micros: [String: Double]
    var scores: MealScores

    /// From a row that carries all three scores; nil while the numbers are still being looked up.
    init?(meal: MealLog) {
        guard let scores = meal.scores else { return nil }
        dishName = meal.displayName
        items = meal.items
        totals = Totals(kcal: meal.totalCalories ?? 0, proteinG: meal.totalProteinG ?? 0, carbsG: meal.totalCarbsG ?? 0, fatG: meal.totalFatG ?? 0, fiberG: meal.totalFiberG ?? 0)
        micros = meal.micros
        self.scores = scores
    }

    init(dishName: String, items: [MealItem], totals: Totals, micros: [String: Double], scores: MealScores) {
        self.dishName = dishName
        self.items = items
        self.totals = totals
        self.micros = micros
        self.scores = scores
    }

    /// The edited meal folded back into the row shape every screen renders.
    func applied(to meal: MealLog) -> MealLog {
        MealLog(
            id: meal.id, loggedAt: meal.loggedAt, mealType: meal.mealType, name: dishName, source: meal.source,
            analysisStatus: meal.analysisStatus, totalCalories: totals.kcal, totalProteinG: totals.proteinG,
            totalCarbsG: totals.carbsG, totalFatG: totals.fatG, photoPaths: meal.photoPaths, analysisError: meal.analysisError,
            totalFiberG: totals.fiberG, items: items, scores: scores, patientNote: meal.patientNote, micros: micros,
            analysisCoverage: meal.analysisCoverage
        )
    }
}

// Post-analysis edit math (the Expo `recompute.ts` + `reprice.ts`): portions rescale LOCALLY off the row's
// own per-gram density; a renamed or hand-added row is UNPRICED and goes to `resolve-foods` — the same pricing
// ladder `analyze-meal` uses — one row at a time, merged back by (name, still-unpriced), never by position.
enum MealEdit {
    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    /// Scale one item's macros to a new portion. Unknown base grams ⇒ only the weight changes.
    static func scale(_ item: MealItem, toGrams newGrams: Double) -> MealItem {
        let grams = max(0, newGrams.rounded())
        var out = item
        out.estimatedGrams = grams
        guard let base = item.estimatedGrams, base > 0 else { return out }
        let r = grams / base
        out.kcal = item.kcal.map { round1($0 * r) }
        out.proteinG = item.proteinG.map { round1($0 * r) }
        out.carbsG = item.carbsG.map { round1($0 * r) }
        out.fatG = item.fatG.map { round1($0 * r) }
        out.fiberG = item.fiberG.map { round1($0 * r) }
        return out
    }

    /// Re-sum per-item macros (kcal whole, macros 1-dp).
    static func totals(of items: [MealItem]) -> MealDraft.Totals {
        func sum(_ key: (MealItem) -> Double?) -> Double { items.reduce(0) { $0 + (key($1) ?? 0) } }
        return MealDraft.Totals(kcal: sum(\.kcal).rounded(), proteinG: round1(sum(\.proteinG)), carbsG: round1(sum(\.carbsG)), fatG: round1(sum(\.fatG)), fiberG: round1(sum(\.fiberG)))
    }

    /// Rebuild the draft around an edited list: new totals + freshly scored composition.
    static func recompute(_ draft: MealDraft, items: [MealItem]) -> MealDraft {
        var out = draft
        out.items = items
        out.totals = totals(of: items)
        out.scores = MealScoring.score(items)
        return out
    }

    /// No macros yet — hand-added, or renamed to a different food. Counts 0 kcal until priced.
    static func isUnpriced(_ item: MealItem) -> Bool { item.kcal == nil }

    /// A renamed row's macros belonged to the OLD food: keep only the member's own name and portion.
    static func stripPricing(_ item: MealItem) -> MealItem {
        MealItem(name: item.name, estimatedGrams: item.estimatedGrams)
    }

    /// Same-position rows whose NAME changed are stripped. Same-length lists only — an add/remove shifts
    /// positions without renaming anything.
    static func withRenamesUnpriced(prev: [MealItem], next: [MealItem]) -> [MealItem] {
        guard prev.count == next.count else { return next }
        return zip(prev, next).map { p, n in p.name != n.name ? stripPricing(n) : n }
    }

    /// A PORTION change on a row with no macros to scale: nothing moves and nothing re-prices unless we say so.
    static func hasUnpricedPortionChange(prev: [MealItem], next: [MealItem]) -> Bool {
        guard prev.count == next.count else { return false }
        return zip(prev, next).contains { p, n in
            p.name == n.name && p.estimatedGrams != n.estimatedGrams && isUnpriced(n)
        }
    }

    struct PricingRequest: Sendable, Equatable, Encodable {
        let name: String
        let grams: Int
    }

    /// The unpriced rows of a list, as `resolve-foods` request entries.
    static func pricingRequests(for items: [MealItem]) -> [PricingRequest] {
        items.filter(isUnpriced)
            .map { PricingRequest(name: $0.name, grams: Int(($0.estimatedGrams ?? 100).rounded())) }
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The slice of `resolve-foods`' answer this module reads. A row it did not identify (`basis: "unknown"`,
    /// `needs_review`, or no number) must STAY unpriced — a zero is not a price.
    struct ResolvedPricing: Sendable, Equatable, Decodable {
        var name: String?
        var estimatedGrams: Double?
        var kcal: Double?
        var proteinG: Double?
        var carbsG: Double?
        var fatG: Double?
        var fiberG: Double?
        var basis: String?
        var needsReview: Bool?
        var foodItemId: String?
        var category: String?

        init(name: String? = nil, estimatedGrams: Double? = nil, kcal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil, fiberG: Double? = nil, basis: String? = nil, needsReview: Bool? = nil, foodItemId: String? = nil, category: String? = nil) {
            self.name = name; self.estimatedGrams = estimatedGrams; self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG
            self.fatG = fatG; self.fiberG = fiberG; self.basis = basis; self.needsReview = needsReview; self.foodItemId = foodItemId; self.category = category
        }

        private enum CodingKeys: String, CodingKey { case name, estimatedGrams, kcal, proteinG, carbsG, fatG, fiberG, basis, needsReview, foodItemId, category }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            estimatedGrams = Self.number(c, .estimatedGrams)
            kcal = Self.number(c, .kcal)
            proteinG = Self.number(c, .proteinG)
            carbsG = Self.number(c, .carbsG)
            fatG = Self.number(c, .fatG)
            fiberG = Self.number(c, .fiberG)
            basis = try? c.decodeIfPresent(String.self, forKey: .basis)
            needsReview = try? c.decodeIfPresent(Bool.self, forKey: .needsReview)
            foodItemId = try? c.decodeIfPresent(String.self, forKey: .foodItemId)
            category = try? c.decodeIfPresent(String.self, forKey: .category)
        }

        private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
            if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
            return nil
        }
    }

    /// Merge one pricing response into the CURRENT list. `requests[j]` ↔ `resolved[j]`; each result finds its row
    /// by (exact name, still unpriced), so rows added/renamed/removed mid-flight are left alone. Returns the names
    /// the ladder could not price — those rows stay unpriced.
    static func mergeResolvedPricing(items: [MealItem], requests: [PricingRequest], resolved: [ResolvedPricing]) -> (items: [MealItem], unresolved: [String]) {
        var out = items
        var used = Set<Int>()
        var unresolved: [String] = []

        for (j, req) in requests.enumerated() {
            guard let idx = out.indices.first(where: { !used.contains($0) && out[$0].name == req.name && isUnpriced(out[$0]) }) else { continue }
            let r = j < resolved.count ? resolved[j] : nil
            guard let r, r.basis != "unknown", r.needsReview != true, let kcal = r.kcal, kcal.isFinite else {
                unresolved.append(req.name)
                continue
            }
            used.insert(idx)
            let row = out[idx]
            var priced = row
            priced.estimatedGrams = Double(req.grams)
            priced.kcal = kcal
            priced.proteinG = r.proteinG
            priced.carbsG = r.carbsG
            priced.fatG = r.fatG
            priced.fiberG = r.fiberG
            if let basis = r.basis { priced.basis = basis }
            if let category = r.category { priced.category = category }
            // The member nudged the portion while the round trip was in flight: keep their grams.
            let target = row.estimatedGrams ?? Double(req.grams)
            out[idx] = target == Double(req.grams) ? priced : scale(priced, toGrams: target)
        }
        return (out, unresolved)
    }

    /// "Appropriate measures": small foods move in 5 g ticks, plates in 10–25 g, big servings in 50 g.
    static func portionStep(_ grams: Double) -> Double {
        if grams <= 30 { return 5 }
        if grams <= 150 { return 10 }
        if grams <= 500 { return 25 }
        return 50
    }

    /// One ± tap: the step for the current size (down: the step of the size just below).
    static func nudged(_ grams: Double, direction: Int) -> Double {
        let step = direction > 0 ? portionStep(grams) : portionStep(max(grams - 1, 1))
        return max(5, grams + Double(direction) * step)
    }

    /// The line the resolver's refusals produce, with the names on screen so the member can act.
    static func unresolvedMessage(_ names: [String]) -> String {
        if names.count == 1 {
            return String(localized: "meal.edit.unresolved.one", defaultValue: "Couldn’t find nutrition for “\(names[0])” · try a more specific name, or remove it.")
        }
        return String(localized: "meal.edit.unresolved.many", defaultValue: "Couldn’t find nutrition for: \(names.joined(separator: ", ")). Try more specific names.")
    }
}
