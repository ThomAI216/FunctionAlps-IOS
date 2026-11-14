import Foundation

/// Names for the meal nutrient list that come from `Localizable.xcstrings` rather than the dictionary
/// (`nb_nutrients.name`, English only). No new nutrient wording: the translated names are the ones the micronutrient
/// pages already use; the fallback names copy the dictionary's English and stand in only when it cannot be read.
enum MealNutrientNames {
    /// The UI is not English: prefer a translated name over the dictionary's English one when one exists.
    static var preferTranslated: Bool {
        !(Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("en")
    }

    /// Keys with a name in both languages.
    static func translated(_ key: String) -> String? {
        switch key {
        case "vitamin_a_mcg": return String(localized: "nutrient.vitamin_a.name", defaultValue: "Vitamin A")
        case "vitamin_c_mg": return String(localized: "nutrient.vitamin_c.name", defaultValue: "Vitamin C")
        case "vitamin_d_mcg": return String(localized: "nutrient.vitamin_d3.name", defaultValue: "Vitamin D3")
        case "vitamin_e_mg": return String(localized: "nutrient.vitamin_e.name", defaultValue: "Vitamin E")
        case "vitamin_k2_mcg": return String(localized: "nutrient.vitamin_k2.name", defaultValue: "Vitamin K2")
        case "b12_mcg": return String(localized: "nutrient.vitamin_b12.name", defaultValue: "Vitamin B12")
        case "folate_mcg": return String(localized: "nutrient.folate.name", defaultValue: "Folate (B9)")
        case "biotin_mcg": return String(localized: "nutrient.biotin.name", defaultValue: "Biotin (B7)")
        case "choline_mg": return String(localized: "nutrient.choline.name", defaultValue: "Choline")
        case "calcium_mg": return String(localized: "nutrient.calcium.name", defaultValue: "Calcium")
        case "iron_mg": return String(localized: "nutrient.iron.name", defaultValue: "Iron")
        case "magnesium_mg": return String(localized: "nutrient.magnesium.name", defaultValue: "Magnesium")
        case "phosphorus_mg": return String(localized: "nutrient.phosphorus.name", defaultValue: "Phosphorus")
        case "potassium_mg": return String(localized: "nutrient.potassium.name", defaultValue: "Potassium")
        case "selenium_mcg": return String(localized: "nutrient.selenium.name", defaultValue: "Selenium")
        case "iodine_mcg": return String(localized: "nutrient.iodine.name", defaultValue: "Iodine")
        case "zinc_mg": return String(localized: "nutrient.zinc.name", defaultValue: "Zinc")
        case "ala_g": return String(localized: "nutrient.ala.name", defaultValue: "ALA (Omega-3)")
        case "epa_mg", "epa_g": return String(localized: "nutrient.epa.name", defaultValue: "EPA (Omega-3)")
        case "dha_mg", "dha_g": return String(localized: "nutrient.dha.name", defaultValue: "DHA (Omega-3)")
        case "omega3_g": return String(localized: "meal.nutrients.name.omega3", defaultValue: "Omega-3")
        case "sodium_mg": return String(localized: "meal.nutrients.name.sodium", defaultValue: "Sodium")
        case "alcohol_g": return String(localized: "meal.nutrients.name.alcohol", defaultValue: "Alcohol")
        case "omega6_omega3_ratio": return String(localized: "meal.nutrients.metric.ratio", defaultValue: "Omega-6 : omega-3")
        case "epa_dha_mg": return String(localized: "meal.nutrients.metric.epaDha", defaultValue: "EPA + DHA")
        default: return nil
        }
    }

    /// Any name the app holds for a legacy key: the translated ones, then the dictionary's English names for the rest
    /// of the 34 legacy keys (shown when the dictionary could not be read).
    static func fallback(_ key: String) -> String? {
        if let name = translated(key) { return name }
        switch key {
        case "sugar_g": return String(localized: "meal.nutrients.name.sugar", defaultValue: "Sugars, total")
        case "saturated_fat_g": return String(localized: "meal.nutrients.name.saturatedFat", defaultValue: "Saturated fat (SFA)")
        case "omega6_g": return String(localized: "meal.nutrients.name.omega6", defaultValue: "Omega-6")
        case "vitamin_k_mcg": return String(localized: "meal.nutrients.name.vitaminK1", defaultValue: "Vitamin K1 (phylloquinone)")
        case "thiamin_mg": return String(localized: "meal.nutrients.name.thiamin", defaultValue: "Thiamin (B1)")
        case "riboflavin_mg": return String(localized: "meal.nutrients.name.riboflavin", defaultValue: "Riboflavin (B2)")
        case "niacin_mg": return String(localized: "meal.nutrients.name.niacin", defaultValue: "Niacin (B3)")
        case "b6_mg": return String(localized: "meal.nutrients.name.b6", defaultValue: "Vitamin B6")
        case "copper_mg": return String(localized: "meal.nutrients.name.copper", defaultValue: "Copper")
        case "manganese_mg": return String(localized: "meal.nutrients.name.manganese", defaultValue: "Manganese")
        case "chromium_mcg": return String(localized: "meal.nutrients.name.chromium", defaultValue: "Chromium")
        default: return nil
        }
    }
}
