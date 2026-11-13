import Foundation

/// What `analyze-meal` recorded about how many nutrients a meal really measured
/// (`resolution_meta.micro_coverage`). Decoded in `Core/API`; absent on meals analysed before it existed.
struct MealMicroCoverage: Sendable, Equatable {
    /// Nutrient keys the food catalogue has (the ceiling for any meal).
    let tracked: Int
    /// Keys with a value from at least one food.
    let measured: Int
    let items: Int
    let itemsFromCatalogue: Int
    /// Keys with a value on some foods but not all (their total is a partial sum).
    let partial: [String]
}

/// Presence rules for micronutrients: "no value" is not zero, and "some meals" is not "all meals".
/// Pure facts about which values exist; the arithmetic stays in `MicroCoverage` / on the server.
enum MicroPresence {
    /// The 34 nutrient keys of the food catalogue, in `micronutrient_totals` naming. Mirrors the server's
    /// `CATALOGUE_MICRO_KEYS` (`_shared/meals/micro-keys.ts`); a test keeps the count.
    static let catalogueKeys: [String] = [
        "sugar_g", "saturated_fat_g", "alcohol_g",
        "omega3_g", "omega6_g", "ala_g", "epa_mg", "dha_mg",
        "vitamin_a_mcg", "vitamin_c_mg", "vitamin_d_mcg", "vitamin_e_mg", "vitamin_k_mcg", "vitamin_k2_mcg",
        "thiamin_mg", "riboflavin_mg", "niacin_mg", "b6_mg", "b12_mcg", "folate_mcg", "biotin_mcg", "choline_mg",
        "calcium_mg", "iron_mg", "magnesium_mg", "phosphorus_mg", "potassium_mg", "sodium_mg", "zinc_mg",
        "selenium_mcg", "iodine_mcg", "copper_mg", "manganese_mg", "chromium_mcg",
    ]

    /// Columns that are empty or nearly empty in the food data: biotin, chromium, vitamin K2.
    static let sparseFields: Set<String> = ["biotin_mcg", "chromium_mcg", "vitamin_k2_mcg"]

    enum Status: Sendable, Equatable {
        /// No meal of the period has a value.
        case noData
        /// Some meals have a value, others do not.
        case partial(mealsWithValue: Int, totalMeals: Int)
        /// Every meal has a value, but a meal's `micro_coverage.partial` lists it: not every food had one.
        case someFoodsMissing
        case measured

        var hasValue: Bool { self != .noData }
    }

    enum Note: Sendable, Equatable {
        case notInFoodData
        case fromMeals(Int, of: Int)
        case someFoodsMissing
    }

    struct Summary: Sendable, Equatable {
        let measured: Int
        let tracked: Int
    }

    /// Meals whose analysis finished; one still being priced has no micros yet and says nothing.
    private static func counted(_ meals: [MealLog]) -> [MealLog] { meals.filter(\.isAnalysed) }

    static func status(field: String, meals: [MealLog]) -> Status {
        let meals = counted(meals)
        let withValue = meals.filter { $0.micros[field] != nil }
        guard !withValue.isEmpty else { return .noData }
        if withValue.count < meals.count { return .partial(mealsWithValue: withValue.count, totalMeals: meals.count) }
        if withValue.contains(where: { $0.microCoverage?.partial.contains(field) == true }) { return .someFoodsMissing }
        return .measured
    }

    /// Status of each tracked nutrient, keyed by its `MicroCoverage` key.
    static func statuses(meals: [MealLog]) -> [String: Status] {
        Dictionary(uniqueKeysWithValues: MicroCoverage.nutrients.map { ($0.key, status(field: $0.field, meals: meals)) })
    }

    static func note(status: Status, field: String) -> Note? {
        switch status {
        case .noData: return sparseFields.contains(field) ? .notInFoodData : nil
        case let .partial(with, total): return .fromMeals(with, of: total)
        case .someFoodsMissing: return .someFoodsMissing
        case .measured: return nil
        }
    }

    /// "N of M measured" for the period. Nil when no meal carries any nutrient value. One meal with
    /// `micro_coverage` uses the server's counts; otherwise it counts catalogue keys present across the meals.
    static func summary(meals: [MealLog]) -> Summary? {
        let meals = counted(meals)
        let present = Set(meals.flatMap { $0.micros.keys }.filter(Set(catalogueKeys).contains))
        guard !present.isEmpty else { return nil }
        let tracked = meals.compactMap { $0.microCoverage?.tracked }.max() ?? catalogueKeys.count
        if meals.count == 1, let c = meals[0].microCoverage { return Summary(measured: c.measured, tracked: c.tracked) }
        return Summary(measured: min(present.count, tracked), tracked: tracked)
    }
}
