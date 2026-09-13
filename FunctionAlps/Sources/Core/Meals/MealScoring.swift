import Foundation

// Meal COMPOSITION scoring v2 — a line-for-line port of `supabase/functions/_shared/meal-scores.ts`, the
// SAME rules engine `analyze-meal` runs, so a meal the member edits on the phone scores identically to a
// freshly analysed one with no round trip. Deterministic and pure: no model participates.
//
//   plants_fibre → gut_score           fibre content and plant variety in the recorded meal
//   fat_quality  → inflammation_score  the fat SOURCES the meal draws on, and its saturated share
//   carb_quality → glycemic_score      how much of the carbohydrate comes with fibre intact
//
// Every string here describes the FOOD, never the person (the legal rule on scores). The legacy column
// names survive only as storage keys (`MealScores`).
enum MealScoring {
    enum FoodGroup: Sendable, Equatable {
        case vegetable, fruit, legume, wholeGrain, refinedGrain, nutSeed, herbSpice
        case fishOily, fishLean, poultry, redMeat, processedMeat, egg, dairy
        case oilUnsat, oilSat
        case sweet, sweetDrink, friedFast
        case other
    }

    enum Band: String, Sendable { case limited, moderate, strong, veryStrong = "very_strong" }
    enum Confidence: String, Sendable { case low, moderate, high }

    struct ScoreResult: Sendable, Equatable {
        /// 0–100, higher is better on ALL THREE.
        let value: Int
        let band: Band
        let confidence: Confidence
        let positive: [String]
        let limiting: [String]
    }

    struct Composition: Sendable, Equatable {
        let plantsFibre: ScoreResult
        let fatQuality: ScoreResult
        let carbQuality: ScoreResult

        /// The legacy triple, for the DB write and every caller that still speaks it.
        var legacy: MealScores { MealScores(inflammation: fatQuality.value, glycemic: carbQuality.value, digestion: plantsFibre.value) }
    }

    // MARK: Classification

    private static let plantGroups: Set<FoodGroup> = [.vegetable, .fruit, .legume, .wholeGrain, .nutSeed]

    /// Word-boundary tokens: membership is an EXACT token match, so "goat" never matches "oat".
    static func tokenise(_ s: String) -> [String] {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return folded.split(whereSeparator: { !($0 >= "a" && $0 <= "z") }).map(String.init).filter { !$0.isEmpty }
    }

    private static func has(_ t: [String], _ words: [String]) -> Bool { words.contains { t.contains($0) } }

    private static let oilyFish = ["salmon", "sardine", "sardines", "mackerel", "herring", "anchovy", "anchovies", "trout", "kipper", "saumon", "maquereau", "hareng"]
    private static let wholeGrain = ["wholegrain", "wholemeal", "wholewheat", "complet", "complets", "complete", "completes", "brown", "oat", "oats", "oatmeal", "porridge", "barley", "rye", "quinoa", "buckwheat", "bulgur", "spelt", "farro", "millet", "sorghum", "freekeh", "avoine", "seigle", "orge", "sarrasin", "epeautre"]
    private static let refinedGrain = ["white", "baguette", "croissant", "brioche", "bagel", "pastry", "cracker", "crackers", "blanc", "blanche"]
    private static let unsatOil = ["olive", "rapeseed", "canola", "sunflower", "linseed", "flaxseed", "walnut", "avocado", "sesame", "colza", "tournesol"]
    private static let satOil = ["butter", "ghee", "lard", "tallow", "dripping", "suet", "coconut", "palm", "margarine", "shortening", "beurre", "saindoux"]
    private static let processedMeat = ["sausage", "sausages", "bacon", "salami", "pepperoni", "chorizo", "ham", "prosciutto", "pancetta", "frankfurter", "hotdog", "mortadella", "saucisse", "saucisson", "jambon", "lardon", "lardons", "charcuterie", "nugget", "nuggets"]
    // "squash" is deliberately absent: it names both a soft drink and a vegetable.
    private static let sweetDrink = ["soda", "cola", "lemonade", "cordial", "juice", "smoothie", "milkshake", "jus", "limonade", "sirop"]
    private static let friedFast = ["fried", "deepfried", "fries", "chips", "crisps", "burger", "cheeseburger", "pizza", "kebab", "tempura", "battered", "breaded", "frite", "frites", "pane", "panee"]
    private static let sweet = ["cake", "biscuit", "cookie", "doughnut", "donut", "candy", "sweets", "chocolate", "brownie", "muffin", "icecream", "sorbet", "jam", "honey", "syrup", "sugar", "gateau", "bonbon", "confiture", "miel", "sucre"]
    private static let legume = ["lentil", "lentils", "chickpea", "chickpeas", "bean", "beans", "pea", "peas", "soy", "soya", "tofu", "tempeh", "edamame", "hummus", "houmous", "lentille", "lentilles", "poischiche", "haricot", "haricots", "feve", "feves", "pois"]
    private static let nutSeed = ["almond", "almonds", "walnut", "walnuts", "cashew", "cashews", "pecan", "pecans", "pistachio", "pistachios", "hazelnut", "hazelnuts", "peanut", "peanuts", "macadamia", "seed", "seeds", "chia", "flax", "linseed", "sesame", "tahini", "sunflower", "pumpkinseed", "amande", "amandes", "noix", "noisette", "graine", "graines"]
    private static let fruit = ["apple", "banana", "orange", "pear", "peach", "plum", "grape", "grapes", "berry", "berries", "strawberry", "strawberries", "blueberry", "blueberries", "raspberry", "raspberries", "blackberry", "mango", "melon", "watermelon", "pineapple", "kiwi", "apricot", "cherry", "cherries", "fig", "figs", "date", "dates", "avocado", "pomme", "banane", "poire", "peche", "raisin", "fraise", "myrtille", "framboise", "abricot", "cerise", "figue", "datte", "avocat"]
    private static let egg = ["egg", "eggs", "omelette", "omelet", "oeuf", "oeufs"]
    private static let fishAny = ["fish", "cod", "haddock", "tuna", "sole", "hake", "pollock", "bass", "bream", "prawn", "prawns", "shrimp", "crab", "lobster", "mussel", "mussels", "scallop", "squid", "poisson", "cabillaud", "thon", "crevette", "crevettes", "moule", "moules"]
    private static let poultry = ["chicken", "turkey", "duck", "poulet", "dinde", "canard", "volaille"]
    private static let redMeat = ["beef", "steak", "pork", "lamb", "veal", "venison", "mutton", "boeuf", "porc", "agneau", "veau"]
    private static let dairy = ["milk", "yogurt", "yoghurt", "cheese", "cream", "creme", "quark", "skyr", "kefir", "ricotta", "mozzarella", "cheddar", "parmesan", "feta", "lait", "fromage", "yaourt"]
    private static let herbSpice = ["herb", "herbs", "spice", "spices", "basil", "parsley", "coriander", "cilantro", "mint", "thyme", "rosemary", "oregano", "dill", "chive", "chives", "sage", "turmeric", "cumin", "paprika", "cinnamon", "ginger", "pepper", "peppercorn", "basilic", "persil", "menthe", "thym", "romarin", "aneth", "curcuma", "cannelle", "gingembre"]
    private static let vegetable = ["vegetable", "vegetables", "potato", "potatoes", "sweetcorn", "corn", "squash", "pumpkin", "courgette", "zucchini", "aubergine", "eggplant", "tomato", "tomatoes", "carrot", "carrots", "broccoli", "cauliflower", "cabbage", "kale", "spinach", "lettuce", "salad", "rocket", "arugula", "leek", "leeks", "onion", "onions", "garlic", "celery", "cucumber", "beetroot", "beet", "turnip", "parsnip", "radish", "asparagus", "artichoke", "fennel", "mushroom", "mushrooms", "pepper", "peppers", "sprouts", "chard", "okra", "legume", "legumes", "pommedeterre", "courgettes", "aubergines", "chou", "epinard", "epinards", "laitue", "poireau", "oignon", "ail", "concombre", "betterave", "champignon", "champignons", "poivron", "carotte", "carottes", "salade", "legume"]
    private static let dairyHead = ["milk", "yogurt", "yoghurt", "cream", "lait", "yaourt", "creme"]
    private static let plantMilkSource: [(String, FoodGroup)] = [
        ("oat", .wholeGrain), ("oats", .wholeGrain), ("rice", .refinedGrain), ("spelt", .wholeGrain),
        ("almond", .nutSeed), ("cashew", .nutSeed), ("hazelnut", .nutSeed), ("walnut", .nutSeed),
        ("soy", .legume), ("soya", .legume), ("pea", .legume),
        ("coconut", .oilSat), ("avoine", .wholeGrain), ("amande", .nutSeed), ("soja", .legume), ("coco", .oilSat),
    ]

    /// The reference category, when specific enough to decide on its own. Category BEATS the name.
    private static func categoryGroup(_ c: String, _ t: [String]) -> FoodGroup? {
        if c.isEmpty { return nil }
        if c.contains("vegetables and vegetable products") { return .vegetable }
        if c.contains("legumes and legume") { return .legume }
        if c.contains("nut and seed") { return .nutSeed }
        if c.contains("spices and herbs") { return .herbSpice }
        if c.contains("fruits and fruit juices") { return has(t, sweetDrink) ? .sweetDrink : .fruit }
        if c.contains("sweets") || c.contains("sugar and confectionery") || c.contains("ice cream") { return .sweet }
        if c.contains("finfish") { return has(t, oilyFish) ? .fishOily : .fishLean }
        if c.contains("poultry") { return .poultry }
        if c.contains("beef products") || c.contains("pork products") || c.contains("lamb, veal") { return .redMeat }
        if c.contains("sausages and luncheon") { return .processedMeat }
        if c.contains("dairy and egg") { return has(t, egg) ? .egg : .dairy }
        if c.contains("milk and milk products") { return .dairy }
        if c.contains("fast foods") || c.contains("snacks") { return .friedFast }
        if c.contains("cereal") || c.contains("baked products") || c.contains("breakfast cereals") || c.contains("grains and pasta") {
            return has(t, wholeGrain) ? .wholeGrain : .refinedGrain
        }
        if c.contains("fats and oils") { return has(t, satOil) ? .oilSat : has(t, unsatOil) ? .oilUnsat : .other }
        return nil
    }

    /// Classify one item: preparation → reference category → head noun → any recognised token.
    static func classify(name: String, category: String? = nil) -> FoodGroup {
        let t = tokenise(name)
        let c = (category ?? "").lowercased()

        if has(t, friedFast) { return .friedFast }
        if has(t, processedMeat) { return .processedMeat }

        if let byCategory = categoryGroup(c, t) { return byCategory }

        let head = t.last ?? ""
        func isHead(_ arr: [String]) -> Bool { arr.contains(head) }
        if isHead(sweetDrink) { return .sweetDrink }
        if isHead(sweet) { return .sweet }
        if isHead(legume) { return .legume }
        if isHead(nutSeed) { return .nutSeed }
        if isHead(fruit) { return .fruit }
        if isHead(oilyFish) { return .fishOily }
        if head == "butter", has(t, nutSeed) { return .nutSeed }
        if dairyHead.contains(head) {
            if let plant = plantMilkSource.first(where: { t.contains($0.0) }) { return plant.1 }
            return .dairy
        }
        if isHead(dairy) { return .dairy }

        if has(t, sweetDrink) { return .sweetDrink }
        if c.contains("fats and oils") || has(t, ["oil", "huile"]) {
            if has(t, satOil) { return .oilSat }
            if has(t, unsatOil) { return .oilUnsat }
        }
        if has(t, satOil) { return .oilSat }
        if has(t, sweet) { return .sweet }
        if has(t, oilyFish) { return .fishOily }
        if has(t, fishAny) { return .fishLean }
        if has(t, egg) { return .egg }
        if has(t, poultry) { return .poultry }
        if has(t, redMeat) { return .redMeat }
        if has(t, dairy) { return .dairy }
        if has(t, nutSeed) { return .nutSeed }
        if has(t, legume) { return .legume }
        if has(t, herbSpice) { return .herbSpice }
        if has(t, wholeGrain) { return .wholeGrain }
        if has(t, refinedGrain + ["bread", "pasta", "rice", "risotto", "noodle", "noodles", "couscous", "pain", "riz"]) { return .refinedGrain }
        if has(t, fruit) { return .fruit }
        if has(t, vegetable) { return .vegetable }

        if c.contains("fruits, vegetables, legumes and nuts") { return .vegetable }
        if c.contains("vegetable") { return .vegetable }
        return .other
    }

    // MARK: Numeric helpers

    private static func clamp01(_ v: Double) -> Double { v < 0 ? 0 : v > 1 ? 1 : v }
    private static func pct(_ v: Double) -> Int { max(0, min(100, Int((v * 100).rounded()))) }
    private static func ramp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { hi == lo ? 0 : clamp01((v - lo) / (hi - lo)) }
    private static func saturating(_ v: Double, _ k: Double) -> Double { v <= 0 ? 0 : 1 - exp(-v / k) }
    private static func band(_ v: Int) -> Band { v >= 80 ? .veryStrong : v >= 60 ? .strong : v >= 40 ? .moderate : .limited }
    private static let basisTrust: [String: Double] = ["exact": 1, "learned": 0.95, "matched": 0.85, "decomposed": 0.75, "estimated": 0.35, "unknown": 0.1]
    private static func confidenceBand(_ t: Double) -> Confidence { t >= 0.8 ? .high : t >= 0.5 ? .moderate : .low }

    private struct Feat {
        let group: FoodGroup
        let grams: Double
        let kcal: Double
        let carbs: Double
        let fiber: Double
        let fat: Double
        let satFat: Double?
        let sugar: Double?
        let omega3: Double?
        let name: String
        let trust: Double
    }

    private struct Totals { var kcal, grams, carbs, fiber, fat: Double }

    /// Distinct plant foods by their longest token (a cheap, stable proxy for the head noun).
    private static func distinctPlants(_ feats: [Feat]) -> (count: Int, herbs: Int) {
        var seen = Set<String>()
        var herbs = 0
        for f in feats {
            if f.group == .herbSpice { herbs += 1; continue }
            guard plantGroups.contains(f.group) else { continue }
            let t = tokenise(f.name)
            var head = t.first ?? f.name.lowercased()
            for tok in t where tok.count > head.count { head = tok }
            seen.insert(head)
        }
        return (seen.count, herbs)
    }

    private static func weightedTrust(_ feats: [Feat]) -> Double {
        let w = feats.reduce(0) { $0 + $1.grams }
        if w <= 0 { return feats.isEmpty ? 0 : feats.reduce(0) { $0 + $1.trust } / Double(feats.count) }
        return feats.reduce(0) { $0 + $1.trust * $1.grams } / w
    }

    private static func trimmed(_ positive: [String], _ limiting: [String]) -> ([String], [String]) {
        (Array(positive.prefix(3)), Array(limiting.prefix(3)))
    }

    // MARK: Score 1 — Plants & Fibre

    private static func scorePlantsFibre(_ feats: [Feat], _ totals: Totals) -> ScoreResult {
        var positive: [String] = []
        var limiting: [String] = []

        let density = totals.kcal > 0 ? totals.fiber / (totals.kcal / 1000) : 0
        let fibrePart = 0.6 * ramp(density, 0, 14) + 0.4 * ramp(totals.fiber, 0, 10)

        let (count, herbs) = distinctPlants(feats)
        let varietyCount = Double(count) + min(Double(herbs) * 0.25, 1)
        let varietyPart = saturating(varietyCount, 2.5)

        let plantGrams = feats.filter { plantGroups.contains($0.group) }.reduce(0) { $0 + $1.grams }
        let sharePart = totals.grams > 0 ? clamp01(plantGrams / totals.grams) : 0

        let value = pct(0.45 * fibrePart + 0.35 * varietyPart + 0.20 * sharePart)

        if totals.fiber >= 8 { positive.append("\(Int(totals.fiber.rounded())) g of fibre") }
        if count >= 4 { positive.append("\(count) different plant foods") } else if count >= 2 { positive.append("\(count) plant foods") }
        if herbs > 0 { positive.append("herbs and spices add variety") }
        if let top = feats.filter({ plantGroups.contains($0.group) }).max(by: { $0.fiber < $1.fiber }), top.fiber >= 3 {
            positive.append("\(top.name) is a strong fibre source")
        }
        if totals.fiber < 5 { limiting.append("little fibre in this meal") }
        if count == 0 { limiting.append("no plant foods recorded") } else if count == 1 { limiting.append("all the plant content came from one food") }
        if sharePart < 0.25, count > 0 { limiting.append("plants are a small part of the plate") }

        let (p, l) = trimmed(positive, limiting)
        return ScoreResult(value: value, band: band(value), confidence: confidenceBand(weightedTrust(feats)), positive: p, limiting: l)
    }

    // MARK: Score 2 — Fat Quality

    private static let fatSourceQuality: [FoodGroup: Double] = [
        .nutSeed: 1, .oilUnsat: 1, .fishOily: 1,
        .fruit: 0.9,
        .fishLean: 0.8, .legume: 0.8, .wholeGrain: 0.75, .vegetable: 0.75,
        .egg: 0.65, .poultry: 0.6,
        .dairy: 0.45, .redMeat: 0.4, .oilSat: 0.3,
        .refinedGrain: 0.3, .sweet: 0.2, .friedFast: 0.1, .processedMeat: 0.1,
        .other: 0.5, .herbSpice: 0.5, .sweetDrink: 0.3,
    ]

    private static func scoreFatQuality(_ feats: [Feat], _ totals: Totals) -> ScoreResult {
        var positive: [String] = []
        var limiting: [String] = []
        let fatBearing = feats.filter { $0.fat > 0.5 }

        if totals.fat < 3 || fatBearing.isEmpty {
            return ScoreResult(value: 60, band: .strong, confidence: .low, positive: [], limiting: ["very little fat in this meal to assess"])
        }

        let fatGrams = max(fatBearing.reduce(0) { $0 + $1.fat }, 1)
        let sourcePart = clamp01(fatBearing.reduce(0) { $0 + (fatSourceQuality[$1.group] ?? 0.5) * $1.fat } / fatGrams)

        let withSat = fatBearing.filter { $0.satFat != nil }
        let satCoverage = withSat.reduce(0) { $0 + $1.fat } / fatGrams
        var unsatPart = sourcePart
        var satShare: Double?
        if satCoverage >= 0.5 {
            let satSum = withSat.reduce(0) { $0 + ($1.satFat ?? 0) }
            let fatSum = max(withSat.reduce(0) { $0 + $1.fat }, 1)
            let share = clamp01(satSum / fatSum)
            satShare = share
            unsatPart = 1 - ramp(share, 0.33, 0.75)
        }

        let o3 = feats.reduce(0) { $0 + ($1.omega3 ?? 0) }
        let o3Part = ramp(o3, 0, 1.5)

        let value = pct(0.55 * sourcePart + 0.35 * unsatPart + 0.10 * o3Part)

        // JS sorts descending by quality then takes the first — the first maximum in list order.
        let best = fatBearing.max(by: { (fatSourceQuality[$0.group] ?? 0.5) < (fatSourceQuality[$1.group] ?? 0.5) })
        let worst = fatBearing.min(by: { (fatSourceQuality[$0.group] ?? 0.5) < (fatSourceQuality[$1.group] ?? 0.5) })
        if let best, (fatSourceQuality[best.group] ?? 0) >= 0.8 { positive.append("fat mostly from \(best.name)") }
        if o3 >= 0.5 { positive.append("contains omega-3 fats") }
        if let satShare, satShare <= 0.33 { positive.append("mostly unsaturated fat") }
        if let satShare, satShare >= 0.5 { limiting.append("a large share of the fat is saturated") }
        if let worst, (fatSourceQuality[worst.group] ?? 1) <= 0.3 { limiting.append("\(worst.name) contributes lower-quality fat") }

        let trust = weightedTrust(fatBearing) * (satCoverage >= 0.5 ? 1 : 0.6)
        let (p, l) = trimmed(positive, limiting)
        return ScoreResult(value: value, band: band(value), confidence: confidenceBand(trust), positive: p, limiting: l)
    }

    // MARK: Score 3 — Carb Quality

    private static let wholeCarbGroups: Set<FoodGroup> = [.wholeGrain, .legume, .vegetable, .fruit, .nutSeed]
    private static let freeSugarGroups: Set<FoodGroup> = [.sweet, .sweetDrink, .friedFast, .refinedGrain]

    private static func scoreCarbQuality(_ feats: [Feat], _ totals: Totals) -> ScoreResult {
        var positive: [String] = []
        var limiting: [String] = []

        if totals.carbs < 5 {
            return ScoreResult(value: 60, band: .strong, confidence: .low, positive: [], limiting: ["very little carbohydrate in this meal to assess"])
        }

        let ratio = totals.fiber / totals.carbs
        let ratioPart = ramp(ratio, 0.02, 0.20)

        let carbGrams = max(feats.reduce(0) { $0 + $1.carbs }, 1)
        let wholeCarbs = feats.filter { wholeCarbGroups.contains($0.group) }.reduce(0) { $0 + $1.carbs }
        let wholePart = clamp01(wholeCarbs / carbGrams)

        let freeSugar = feats.filter { freeSugarGroups.contains($0.group) }.reduce(0) { $0 + ($1.sugar ?? 0) }
        let freeSugarPart = 1 - ramp(freeSugar, 5, 25)

        let value = pct(0.40 * ratioPart + 0.35 * wholePart + 0.25 * freeSugarPart)

        if ratio >= 0.1 { positive.append("carbohydrate comes with its fibre") }
        if let topWhole = feats.filter({ wholeCarbGroups.contains($0.group) }).max(by: { $0.carbs < $1.carbs }), topWhole.carbs >= 5 {
            positive.append("\(topWhole.name) is an intact carbohydrate source")
        }
        if freeSugar > 0, freeSugar < 5 { positive.append("little added sugar") }

        if ratio < 0.05 { limiting.append("carbohydrate arrives with little fibre") }
        if wholePart < 0.4 {
            let topRefined = feats.filter { !wholeCarbGroups.contains($0.group) && $0.carbs > 0 }.max(by: { $0.carbs < $1.carbs })
            limiting.append(topRefined.map { "most carbohydrate came from \($0.name)" } ?? "most carbohydrate came from refined sources")
        }
        if freeSugar >= 10 { limiting.append("about \(Int(freeSugar.rounded())) g sugar from sweetened foods") }

        let carbBearing = feats.filter { $0.carbs > 0.5 }
        let (p, l) = trimmed(positive, limiting)
        return ScoreResult(value: value, band: band(value), confidence: confidenceBand(weightedTrust(carbBearing)), positive: p, limiting: l)
    }

    // MARK: Assembly

    private static func featurise(_ items: [MealItem]) -> [Feat] {
        items.map { it in
            let m = it.micros
            let grams = it.estimatedGrams ?? 0
            return Feat(
                group: classify(name: it.name, category: it.category),
                // 50 g when the portion is unknown, so an unweighed item still participates.
                grams: grams > 0 ? grams : 50,
                kcal: it.kcal ?? 0,
                carbs: it.carbsG ?? 0,
                fiber: it.fiberG ?? 0,
                fat: it.fatG ?? 0,
                satFat: m["saturated_fat_g"],
                sugar: m["sugar_g"],
                omega3: m["omega3_g"],
                name: it.name.isEmpty ? "item" : it.name,
                trust: basisTrust[it.basis ?? "matched"] ?? 0.85
            )
        }
    }

    /// The three composition scores for one meal.
    static func composition(of items: [MealItem]) -> Composition {
        let feats = featurise(items)
        if feats.isEmpty {
            let empty = ScoreResult(value: 60, band: .strong, confidence: .low, positive: [], limiting: ["no foods recorded"])
            return Composition(plantsFibre: empty, fatQuality: empty, carbQuality: empty)
        }
        var totals = Totals(
            kcal: feats.reduce(0) { $0 + $1.kcal },
            grams: feats.reduce(0) { $0 + $1.grams },
            carbs: feats.reduce(0) { $0 + $1.carbs },
            fiber: feats.reduce(0) { $0 + $1.fiber },
            fat: feats.reduce(0) { $0 + $1.fat }
        )
        if totals.kcal <= 0 { totals.kcal = feats.reduce(0) { $0 + $1.carbs * 4 + $1.fat * 9 } }
        return Composition(
            plantsFibre: scorePlantsFibre(feats, totals),
            fatQuality: scoreFatQuality(feats, totals),
            carbQuality: scoreCarbQuality(feats, totals)
        )
    }

    /// The legacy triple (`inflammation_score` / `glycemic_score` / `gut_score`) — storage keys, not claims.
    static func score(_ items: [MealItem]) -> MealScores { composition(of: items).legacy }
}
