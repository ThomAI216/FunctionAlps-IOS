import Foundation

/// Micronutrient coverage — the Expo `lib/data/nutrients.ts` RDA table and `getOverallCoverage`,
/// summed from each meal's `micronutrient_totals`. Coverage is capped per nutrient (over-eating
/// vitamin C does not cover a magnesium gap), then averaged across the 21 tracked nutrients.
/// Arithmetic on server-written numbers, not scoring: the same numbers the web app shows.
enum MicroCoverage {
    struct Nutrient: Sendable {
        let key: String
        /// The `micronutrient_totals` field the edge functions write.
        let field: String
        let rdaMale: Double
        let rdaFemale: Double
    }

    static let nutrients: [Nutrient] = [
        Nutrient(key: "vitamin_d3", field: "vitamin_d_mcg", rdaMale: 50, rdaFemale: 50),
        Nutrient(key: "vitamin_c", field: "vitamin_c_mg", rdaMale: 90, rdaFemale: 75),
        Nutrient(key: "vitamin_b12", field: "b12_mcg", rdaMale: 2.4, rdaFemale: 2.4),
        Nutrient(key: "folate", field: "folate_mcg", rdaMale: 400, rdaFemale: 400),
        Nutrient(key: "vitamin_a", field: "vitamin_a_mcg", rdaMale: 900, rdaFemale: 700),
        Nutrient(key: "vitamin_k2", field: "vitamin_k2_mcg", rdaMale: 120, rdaFemale: 90),
        Nutrient(key: "vitamin_e", field: "vitamin_e_mg", rdaMale: 15, rdaFemale: 15),
        Nutrient(key: "biotin", field: "biotin_mcg", rdaMale: 30, rdaFemale: 30),
        Nutrient(key: "magnesium", field: "magnesium_mg", rdaMale: 420, rdaFemale: 320),
        Nutrient(key: "iron", field: "iron_mg", rdaMale: 8, rdaFemale: 18),
        Nutrient(key: "zinc", field: "zinc_mg", rdaMale: 11, rdaFemale: 8),
        Nutrient(key: "calcium", field: "calcium_mg", rdaMale: 1000, rdaFemale: 1000),
        Nutrient(key: "selenium", field: "selenium_mcg", rdaMale: 55, rdaFemale: 55),
        Nutrient(key: "iodine", field: "iodine_mcg", rdaMale: 150, rdaFemale: 150),
        Nutrient(key: "potassium", field: "potassium_mg", rdaMale: 3400, rdaFemale: 2600),
        Nutrient(key: "phosphorus", field: "phosphorus_mg", rdaMale: 700, rdaFemale: 700),
        Nutrient(key: "omega3", field: "omega3_g", rdaMale: 1.6, rdaFemale: 1.1),
        Nutrient(key: "ala", field: "ala_g", rdaMale: 1.6, rdaFemale: 1.1),
        Nutrient(key: "epa", field: "epa_mg", rdaMale: 500, rdaFemale: 500),
        Nutrient(key: "dha", field: "dha_mg", rdaMale: 500, rdaFemale: 500),
        Nutrient(key: "choline", field: "choline_mg", rdaMale: 550, rdaFemale: 425),
    ]

    /// Per-nutrient sums over the meals, keyed by nutrient key.
    static func consumed(from meals: [MealLog]) -> [String: Double] {
        var out: [String: Double] = [:]
        for n in nutrients {
            out[n.key] = meals.reduce(0) { $0 + ($1.micros[n.field] ?? 0) }
        }
        return out
    }

    /// Whether any meal carries a micro at all — without it the coverage is "no data", not zero.
    static func hasMicros(_ meals: [MealLog]) -> Bool {
        meals.contains { meal in meal.micros.values.contains { $0 > 0 } }
    }

    /// 0–100 mean coverage (each nutrient capped at 100 %), the Expo `getOverallCoverage`. Nil when no
    /// meal carries micros. `sex` nil → female targets, the web default.
    static func overall(meals: [MealLog], sex: MemberProfile.Sex?) -> Int? {
        guard !meals.isEmpty, hasMicros(meals) else { return nil }
        let sums = consumed(from: meals)
        let male = sex == .male
        let total = nutrients.reduce(0.0) { acc, n in
            let target = male ? n.rdaMale : n.rdaFemale
            return acc + min((sums[n.key] ?? 0) / target, 1)
        }
        return Int((total / Double(nutrients.count) * 100).rounded())
    }

    /// The Expo `macroProximityScore`: mean adherence of P/C/F to their targets (capped at 100 %). Nil
    /// without targets.
    static func macroProximity(protein: Double, carbs: Double, fat: Double, targetProtein: Int?, targetCarbs: Int?, targetFat: Int?) -> Int? {
        let pairs: [(Double, Int?)] = [(protein, targetProtein), (carbs, targetCarbs), (fat, targetFat)]
        let ratios = pairs.compactMap { value, target -> Double? in
            guard let target, target > 0 else { return nil }
            return min(1, value / Double(target))
        }
        guard ratios.count == 3 else { return nil }
        return Int((ratios.reduce(0, +) / 3 * 100).rounded())
    }
}
