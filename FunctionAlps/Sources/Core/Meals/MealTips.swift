import Foundation

/// Rotating meal-time tips for the analysing screen — the Expo `lib/meal-log/tips.ts` list, selected
/// by time-of-day first. Each tip has a stable `id` (a future "bookmark" hook) and an `action`: one
/// concrete, do-it-today line.
struct MealTip: Sendable, Equatable, Identifiable {
    enum DayPart: Sendable, Equatable {
        case morning, afternoon, evening, night

        /// morning 5–11 · afternoon 11–17 · evening 17–22 · night 22–5
        static func current(hour: Int) -> DayPart {
            if hour >= 5 && hour < 11 { return .morning }
            if hour >= 11 && hour < 17 { return .afternoon }
            if hour >= 17 && hour < 22 { return .evening }
            return .night
        }
    }

    enum Kind: Sendable, Equatable {
        case food, move, recovery, fact

        var label: String {
            switch self {
            case .food: String(localized: "tip.kind.food", defaultValue: "Food")
            case .move: String(localized: "tip.kind.move", defaultValue: "Movement")
            case .recovery: String(localized: "tip.kind.recovery", defaultValue: "Recovery")
            case .fact: String(localized: "tip.kind.fact", defaultValue: "Did you know")
            }
        }
    }

    let id: String
    let kind: Kind
    /// Empty = any time.
    let dayParts: [DayPart]
    let text: String
    let action: String
}

enum MealTips {
    /// Tips for the moment, in the Expo order minus the objective preference (the phone does not
    /// carry the onboarding objectives yet): universal facts first, then the day-part's own tips.
    static func select(dayPart: DayPart, all: [MealTip] = MealTips.all) -> [MealTip] {
        let pool = all.filter { $0.dayParts.isEmpty || $0.dayParts.contains(dayPart) }
        let dayPartFirst = pool.filter { !$0.dayParts.isEmpty }
        let universal = pool.filter { $0.dayParts.isEmpty }
        return dayPartFirst + universal
    }

    typealias DayPart = MealTip.DayPart

    static let all: [MealTip] = [
        MealTip(id: "am_protein", kind: .food, dayParts: [.morning],
                text: String(localized: "tip.am_protein.text", defaultValue: "Front-load protein at breakfast · it steadies energy and curbs afternoon cravings."),
                action: String(localized: "tip.am_protein.action", defaultValue: "Add eggs, yoghurt or a protein shake tomorrow morning and feel the afternoon dip fade.")),
        MealTip(id: "am_slow_sugars", kind: .food, dayParts: [.morning],
                text: String(localized: "tip.am_slow_sugars.text", defaultValue: "Go easy on fast sugars this morning · pair any carbs with protein or fat to soften the spike."),
                action: String(localized: "tip.am_slow_sugars.action", defaultValue: "Swap the pastry for protein and fruit today and keep your energy flat, not spiky.")),
        MealTip(id: "am_light", kind: .recovery, dayParts: [.morning],
                text: String(localized: "tip.am_light.text", defaultValue: "Step into daylight within an hour of waking · it anchors your energy today and your sleep tonight."),
                action: String(localized: "tip.am_light.action", defaultValue: "Get 5 minutes of morning light today and fall asleep easier tonight.")),
        MealTip(id: "am_hydrate", kind: .fact, dayParts: [.morning],
                text: String(localized: "tip.am_hydrate.text", defaultValue: "Water before coffee · much of morning fog is just mild dehydration."),
                action: String(localized: "tip.am_hydrate.action", defaultValue: "Drink a glass of water before your coffee today and watch the fog lift.")),
        MealTip(id: "am_mind", kind: .food, dayParts: [.morning],
                text: String(localized: "tip.am_mind.text", defaultValue: "A protein breakfast steadies mood and focus · the brain runs poorly on sugar swings."),
                action: String(localized: "tip.am_mind.action", defaultValue: "Make breakfast protein-first today and notice steadier focus all morning.")),
        MealTip(id: "pm_walk", kind: .move, dayParts: [.afternoon],
                text: String(localized: "tip.pm_walk.text", defaultValue: "A 10-minute walk after eating blunts the glucose rise and eases digestion."),
                action: String(localized: "tip.pm_walk.action", defaultValue: "Walk for 10 minutes after this meal and blunt the post-lunch slump.")),
        MealTip(id: "pm_plate", kind: .food, dayParts: [.afternoon],
                text: String(localized: "tip.pm_plate.text", defaultValue: "Build lunch around a palm of protein, a fist of veg, a thumb of healthy fat."),
                action: String(localized: "tip.pm_plate.action", defaultValue: "Build your next plate this way and feel full without the heaviness.")),
        MealTip(id: "pm_coffee", kind: .fact, dayParts: [.afternoon],
                text: String(localized: "tip.pm_coffee.text", defaultValue: "Caffeine lingers 6+ hours · a late coffee quietly frays tonight’s sleep."),
                action: String(localized: "tip.pm_coffee.action", defaultValue: "Skip coffee after 2pm today and let tonight’s sleep reward you.")),
        MealTip(id: "pm_fibre", kind: .food, dayParts: [.afternoon],
                text: String(localized: "tip.pm_fibre.text", defaultValue: "Add a handful of fibre-rich veg · your gut bugs turn it into anti-inflammatory fuel."),
                action: String(localized: "tip.pm_fibre.action", defaultValue: "Add an extra handful of veg to lunch today and feed a calmer gut.")),
        MealTip(id: "eve_lighter", kind: .food, dayParts: [.evening],
                text: String(localized: "tip.eve_lighter.text", defaultValue: "Keep dinner a little lighter · your gut rests best when you do."),
                action: String(localized: "tip.eve_lighter.action", defaultValue: "Keep tonight’s dinner lighter and wake up less sluggish.")),
        MealTip(id: "eve_earlier", kind: .recovery, dayParts: [.evening],
                text: String(localized: "tip.eve_earlier.text", defaultValue: "Finish eating 2 to 3 hours before bed · late meals tax sleep and recovery."),
                action: String(localized: "tip.eve_earlier.action", defaultValue: "Eat a little earlier tonight and give your sleep room to do its work.")),
        MealTip(id: "eve_protein", kind: .food, dayParts: [.evening],
                text: String(localized: "tip.eve_protein.text", defaultValue: "Include protein at dinner · overnight is when muscle repairs."),
                action: String(localized: "tip.eve_protein.action", defaultValue: "Add protein to dinner tonight and recover stronger overnight.")),
        MealTip(id: "eve_winddown", kind: .recovery, dayParts: [.evening],
                text: String(localized: "tip.eve_winddown.text", defaultValue: "Dim the lights after dinner · it tells your body the day is closing."),
                action: String(localized: "tip.eve_winddown.action", defaultValue: "Dim the lights an hour before bed tonight and fall asleep faster.")),
        MealTip(id: "night_snack", kind: .food, dayParts: [.night],
                text: String(localized: "tip.night_snack.text", defaultValue: "Late cravings spike you before bed · protein or a little fat won’t."),
                action: String(localized: "tip.night_snack.action", defaultValue: "If you snack tonight, reach for protein or fat and protect your sleep.")),
        MealTip(id: "night_tea", kind: .recovery, dayParts: [.night],
                text: String(localized: "tip.night_tea.text", defaultValue: "A warm, caffeine-free tea can settle the nervous system before sleep."),
                action: String(localized: "tip.night_tea.action", defaultValue: "Swap the screen for a warm tea tonight and let your system settle.")),
        MealTip(id: "any_omega3", kind: .food, dayParts: [],
                text: String(localized: "tip.any_omega3.text", defaultValue: "Oily fish, walnuts, flax · omega-3s quietly turn down the body’s inflammation dial."),
                action: String(localized: "tip.any_omega3.action", defaultValue: "Add oily fish or walnuts this week and turn down the inflammation dial.")),
        MealTip(id: "any_fermented", kind: .food, dayParts: [],
                text: String(localized: "tip.any_fermented.text", defaultValue: "A spoon of fermented food (kefir, kimchi, yoghurt) feeds a calmer gut."),
                action: String(localized: "tip.any_fermented.action", defaultValue: "Add a spoon of kefir or kimchi today and feed a calmer gut.")),
        MealTip(id: "any_chew", kind: .fact, dayParts: [],
                text: String(localized: "tip.any_chew.text", defaultValue: "Chew slowly · digestion starts in the mouth, and it gives your brain time to feel full."),
                action: String(localized: "tip.any_chew.action", defaultValue: "Slow down and chew fully at your next meal · digestion and fullness both improve.")),
        MealTip(id: "any_colour", kind: .food, dayParts: [],
                text: String(localized: "tip.any_colour.text", defaultValue: "Eat the rainbow · different plant colours carry different protective compounds."),
                action: String(localized: "tip.any_colour.action", defaultValue: "Add one new colour to your plate today and widen your protective compounds.")),
        MealTip(id: "any_magnesium", kind: .food, dayParts: [],
                text: String(localized: "tip.any_magnesium.text", defaultValue: "Leafy greens, pumpkin seeds, dark chocolate · magnesium supports calm and sleep."),
                action: String(localized: "tip.any_magnesium.action", defaultValue: "Add greens or pumpkin seeds today and support a calmer evening.")),
        MealTip(id: "any_protein_target", kind: .food, dayParts: [],
                text: String(localized: "tip.any_protein_target.text", defaultValue: "Aim for protein at every meal · it protects muscle and steadies appetite."),
                action: String(localized: "tip.any_protein_target.action", defaultValue: "Anchor your next meal with protein and steady your appetite for hours.")),
        MealTip(id: "any_strength", kind: .move, dayParts: [],
                text: String(localized: "tip.any_strength.text", defaultValue: "Muscle is the organ of longevity · a little resistance work protects it for decades."),
                action: String(localized: "tip.any_strength.action", defaultValue: "Fit in 10 minutes of resistance today and invest in decades of strength.")),
        MealTip(id: "any_stress_breath", kind: .recovery, dayParts: [],
                text: String(localized: "tip.any_stress_breath.text", defaultValue: "Stress shuts digestion down · a few slow breaths reopen the gut-brain line."),
                action: String(localized: "tip.any_stress_breath.action", defaultValue: "Take three slow breaths before your next meal and digest with ease.")),
        MealTip(id: "any_hormone_fat", kind: .food, dayParts: [],
                text: String(localized: "tip.any_hormone_fat.text", defaultValue: "Don’t fear healthy fats · olive oil, avocado and eggs are raw material for hormones."),
                action: String(localized: "tip.any_hormone_fat.action", defaultValue: "Add olive oil or avocado today and give your hormones their raw materials.")),
        MealTip(id: "any_spice", kind: .food, dayParts: [],
                text: String(localized: "tip.any_spice.text", defaultValue: "Turmeric, ginger, garlic · everyday spices with quiet anti-inflammatory effects."),
                action: String(localized: "tip.any_spice.action", defaultValue: "Add turmeric or ginger to a meal today for a quiet anti-inflammatory boost.")),
        MealTip(id: "any_iron", kind: .food, dayParts: [],
                text: String(localized: "tip.any_iron.text", defaultValue: "Tired often? Iron-rich foods (red meat, lentils, spinach) feed steady energy."),
                action: String(localized: "tip.any_iron.action", defaultValue: "Add lentils, spinach or red meat this week and lift flagging energy.")),
        MealTip(id: "fact_microbiome", kind: .fact, dayParts: [],
                text: String(localized: "tip.fact_microbiome.text", defaultValue: "Your gut hosts trillions of microbes · what you eat reshapes them within days."),
                action: String(localized: "tip.fact_microbiome.action", defaultValue: "Feed your microbes one extra plant today and shift the balance in days.")),
        MealTip(id: "fact_walk", kind: .fact, dayParts: [],
                text: String(localized: "tip.fact_walk.text", defaultValue: "Even a slow post-meal walk can cut the blood-sugar rise by up to a third."),
                action: String(localized: "tip.fact_walk.action", defaultValue: "Walk for 10 minutes after this meal and flatten the sugar curve.")),
        MealTip(id: "fact_hydration", kind: .fact, dayParts: [],
                text: String(localized: "tip.fact_hydration.text", defaultValue: "Mild dehydration can read as hunger and fatigue · water first, snack second."),
                action: String(localized: "tip.fact_hydration.action", defaultValue: "Drink water the next time you feel snacky and see if the craving fades.")),
        MealTip(id: "fact_protein_thermic", kind: .fact, dayParts: [],
                text: String(localized: "tip.fact_protein_thermic.text", defaultValue: "Protein costs more energy to digest than carbs or fat · it quietly works for you."),
                action: String(localized: "tip.fact_protein_thermic.action", defaultValue: "Make protein the centre of your next meal and let it work for you.")),
        MealTip(id: "fact_fibre", kind: .fact, dayParts: [],
                text: String(localized: "tip.fact_fibre.text", defaultValue: "Most people get half the fibre they need · it’s the simplest gut upgrade."),
                action: String(localized: "tip.fact_fibre.action", defaultValue: "Add one fibre-rich food today and take the easiest gut win there is.")),
        MealTip(id: "fact_sleep_appetite", kind: .fact, dayParts: [],
                text: String(localized: "tip.fact_sleep_appetite.text", defaultValue: "One short night makes the body crave more sugar the next day · sleep is appetite control."),
                action: String(localized: "tip.fact_sleep_appetite.action", defaultValue: "Protect tonight’s sleep and notice fewer cravings tomorrow.")),
    ]
}
