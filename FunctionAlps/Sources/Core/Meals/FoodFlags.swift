import SwiftUI

/// Per-ingredient flags emitted by `analyze-meal` (`ai_identified_foods[].flags`) — the Expo
/// `lib/meal-log/food-flags.ts` registry with its icon colours (`food-flag-icons.tsx`), drawn
/// here with SF Symbols. Unknown keys render nothing rather than a wrong badge.
enum FoodFlag: String, CaseIterable, Sendable, Identifiable {
    case inflammatory, antiInflammatory, fiber, protein, omega3, probiotic, micronutrientDense
    case antioxidant, healthyFats, boneSupport, hydrating, fastSugars, sodium, ultraProcessed, allergen

    var id: String { rawValue }

    enum Tone { case good, watch }

    var tone: Tone {
        switch self {
        case .inflammatory, .fastSugars, .sodium, .ultraProcessed, .allergen: .watch
        default: .good
        }
    }

    var color: Color {
        switch self {
        case .inflammatory: Color(hex: 0xC0453A)
        case .antiInflammatory: Color(hex: 0x3F7FC4)
        case .fiber: Color(hex: 0xD4A84E)
        case .protein: Color(hex: 0xE0654F)
        case .omega3: Color(hex: 0x6C8AE4)
        case .probiotic: Color(hex: 0x4A8A5C)
        case .micronutrientDense: Color(hex: 0x8B5FBF)
        case .antioxidant: Color(hex: 0xB03A5C)
        case .healthyFats: Color(hex: 0x7FA05A)
        case .boneSupport: Color(hex: 0xA8A79E)
        case .hydrating: Color(hex: 0x38A3C8)
        case .fastSugars: Color(hex: 0xD98A2B)
        case .sodium: Color(hex: 0x7A796F)
        case .ultraProcessed: Color(hex: 0x9C6B45)
        case .allergen: Color(hex: 0xC48B35)
        }
    }

    var symbol: String {
        switch self {
        case .inflammatory: "flame"
        case .antiInflammatory: "flame.slash"
        case .fiber: "leaf"
        case .protein: "fork.knife"
        case .omega3: "fish"
        case .probiotic: "microbe"
        case .micronutrientDense: "diamond"
        case .antioxidant: "sparkles"
        case .healthyFats: "drop.halffull"
        case .boneSupport: "figure.stand"
        case .hydrating: "drop"
        case .fastSugars: "cube"
        case .sodium: "square.grid.3x3"
        case .ultraProcessed: "shippingbox"
        case .allergen: "exclamationmark.triangle"
        }
    }

    var label: String {
        switch self {
        case .inflammatory: String(localized: "flag.inflammatory", defaultValue: "Inflammatory")
        case .antiInflammatory: String(localized: "flag.antiInflammatory", defaultValue: "Anti-inflammatory")
        case .fiber: String(localized: "flag.fiber", defaultValue: "Fiber source")
        case .protein: String(localized: "flag.protein", defaultValue: "Protein source")
        case .omega3: String(localized: "flag.omega3", defaultValue: "Omega-3 rich")
        case .probiotic: String(localized: "flag.probiotic", defaultValue: "Probiotic")
        case .micronutrientDense: String(localized: "flag.micronutrientDense", defaultValue: "Nutrient dense")
        case .antioxidant: String(localized: "flag.antioxidant", defaultValue: "Antioxidant")
        case .healthyFats: String(localized: "flag.healthyFats", defaultValue: "Healthy fats")
        case .boneSupport: String(localized: "flag.boneSupport", defaultValue: "Bone support")
        case .hydrating: String(localized: "flag.hydrating", defaultValue: "Hydrating")
        case .fastSugars: String(localized: "flag.fastSugars", defaultValue: "Fast sugars")
        case .sodium: String(localized: "flag.sodium", defaultValue: "High sodium")
        case .ultraProcessed: String(localized: "flag.ultraProcessed", defaultValue: "Ultra-processed")
        case .allergen: String(localized: "flag.allergen", defaultValue: "Common allergen")
        }
    }

    /// The flags of one item, in registry order, unknown keys dropped.
    static func flags(of item: MealItem) -> [FoodFlag] {
        let set = Set(item.flags)
        return allCases.filter { set.contains($0.rawValue) }
    }

    /// Every flag present in a meal — the legend under the ingredient list.
    static func flags(in items: [MealItem]) -> [FoodFlag] {
        let set = Set(items.flatMap(\.flags))
        return allCases.filter { set.contains($0.rawValue) }
    }
}

struct FoodFlagIcon: View {
    let flag: FoodFlag
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: flag.symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(flag.color)
            .frame(width: size + 2, height: size + 2)
            .accessibilityLabel(flag.label)
    }
}
