import Foundation

/// The fourth macro-page entry: energy. The Expo `MACRO_EDUCATION` explains protein, carbs and fat
/// only; the phone's per-macro page also opens from the Calories row, so this hand-written entry
/// (EN/FR in the string catalog) carries what a member needs to read about calories — the same shape
/// as the generated entries so the page renders it identically.
extension MacroEducation {
    static var energy: Entry {
        Entry(
            key: "kcal",
            title: String(localized: "macroEdu.kcal.title", defaultValue: "Calories"),
            emoji: "🔥",
            tagline: String(localized: "macroEdu.kcal.tagline", defaultValue: "The energy your day runs on"),
            why: String(localized: "macroEdu.kcal.why", defaultValue: "A calorie is a unit of energy. Your body spends energy all day — most of it just to keep you alive (your basal metabolism), the rest on movement and digestion. Your daily target starts from that estimate (TDEE), then moves up or down with your objective: a moderate deficit to lose fat, a small surplus to build muscle, or maintenance. Where the calories come from matters as much as how many: protein and fibre-rich carbs keep you full and steady; refined sugar and alcohol do not."),
            bestSources: [
                String(localized: "macroEdu.kcal.source.0", defaultValue: "Whole foods over ultra-processed"),
                String(localized: "macroEdu.kcal.source.1", defaultValue: "Protein at every meal"),
                String(localized: "macroEdu.kcal.source.2", defaultValue: "Vegetables and legumes for volume"),
                String(localized: "macroEdu.kcal.source.3", defaultValue: "Healthy fats in measured amounts"),
            ],
            timing: String(localized: "macroEdu.kcal.timing", defaultValue: "Spread energy across your meals rather than loading the evening. A protein-first breakfast steadies appetite; the largest carb portion sits best around your most active hours."),
            myths: [
                String(localized: "macroEdu.kcal.myth.0", defaultValue: "Myth: eating as little as possible is best (large deficits cost muscle, sleep and hormones — a moderate one is what lasts)"),
                String(localized: "macroEdu.kcal.myth.1", defaultValue: "Myth: a calorie is a calorie (the same energy from protein, fibre-rich carbs or sugar does not have the same effect on hunger, blood sugar or body composition)"),
            ]
        )
    }

    /// The entry for a macro bar key: `kcal`, `protein`, `carbs`, `fat`.
    static func entry(for key: String) -> Entry? {
        key == "kcal" ? energy : entries.first { $0.key == key }
    }
}
