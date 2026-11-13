import Foundation

// The clinician's meal plan as the member sees it (menus programme, P6). The server decides everything
// here: which plan is in force, what each day holds after the member's own swaps, which meals break the
// member's exclusions, and the grocery list. The app only shows it. Wire decoding lives in `Core/API/MealPlanRows.swift`.

/// `member_meal_plan(p_from, p_to)`: a run of days, each with its planned meals. Dates are `yyyy-MM-dd`
/// strings in the MEMBER's time zone (the server's "today"), never device dates.
struct MealPlanRange: Sendable, Equatable {
    /// First day of the range: the server's today.
    let from: String
    let to: String
    let plans: [PlanSummary]
    let days: [PlanDay]

    static let empty = MealPlanRange(from: "", to: "", plans: [], days: [])

    var isEmpty: Bool { days.isEmpty }

    func plan(for day: PlanDay) -> PlanSummary? {
        plans.first { $0.id == day.planId } ?? plans.first
    }
}

struct PlanSummary: Sendable, Equatable, Identifiable {
    let id: String
    let title: String?
    let startDate: String
    let endDate: String
    let people: Double?
    /// Calories are shown to the member only when the plan says so (`meal_plans.show_calories`).
    let showCalories: Bool
    /// `meal_plans.allow_swaps`: false hides every "Swap" and "Make it…".
    let allowSwaps: Bool
}

struct PlanDay: Sendable, Equatable, Identifiable {
    let date: String
    let planId: String?
    let meals: [PlannedMeal]

    var id: String { date }
}

struct PlannedMeal: Sendable, Equatable, Identifiable {
    let slotId: String
    let momentUid: String?
    /// The clinician's own moment name, when it has one ("mid-morning"); the type below is what the app groups by.
    let moment: String?
    let mealType: MealLog.MealType
    /// The clinician's note on this meal: "Why this meal".
    let note: String?
    /// Portions ONE person eats.
    let portions: Double?
    /// Portions cooked for the slot.
    let servings: Double?
    let swapped: Bool
    let swapKind: String?
    let recipe: PlannedRecipe
    /// The recipe the clinician prescribed, when the member changed it.
    let prescribedId: String?
    let prescribedTitle: String?
    /// The recipe in force now breaks the member's exclusions: never offered as "to eat".
    let excluded: Bool
    let alternativeIds: [String]
    /// The meal log of "I ate this" for this day, when there is one.
    let loggedMealId: String?

    var id: String { slotId }
    var isLogged: Bool { loggedMealId != nil }
}

struct PlannedRecipe: Sendable, Equatable {
    let id: String
    let title: String
    let slug: String?
    let imagePath: String?
    let prepMinutes: Int?
    let cookMinutes: Int?
    let servings: Double?
    let variantKind: String?
    /// A recipe the member wrote themselves.
    let own: Bool
    /// Present only when the plan shows calories.
    let kcalPerServing: Double?

    var totalMinutes: Int? {
        let sum = (prepMinutes ?? 0) + (cookMinutes ?? 0)
        return sum > 0 ? sum : nil
    }
}

/// One row of `member_swap_candidates`.
struct SwapCandidate: Sendable, Equatable, Identifiable {
    /// alternative · prescribed · variant · library · mine
    enum Source: String, Sendable { case alternative, prescribed, variant, library, mine }

    let recipeId: String
    let title: String
    let source: Source
    let variantKind: String?
    let prepMinutes: Int?
    let cookMinutes: Int?
    let imagePath: String?
    let isCurrent: Bool

    var id: String { recipeId }
    var totalMinutes: Int? {
        let sum = (prepMinutes ?? 0) + (cookMinutes ?? 0)
        return sum > 0 ? sum : nil
    }
}

/// `member_log_planned_meal`: the meal log the server wrote (or the one already there).
struct PlannedMealLog: Sendable, Equatable {
    let mealLogId: String
    let created: Bool
}

/// `member_swap_meal`.
struct SwapOutcome: Sendable, Equatable {
    let changed: Bool
    let recipeId: String?
    let kind: String?
}

// MARK: Recipe card

/// A recipe the member may read (RLS: approved, member-visible, never a book recipe).
struct RecipeCard: Sendable, Equatable {
    let id: String
    let title: String
    let bodyMd: String
    let steps: [String]
    let servings: Double?
    let prepMinutes: Int?
    let cookMinutes: Int?
    let yieldText: String?
    let variantKind: String?
    let ingredients: [RecipeIngredient]
    let nutrition: RecipeNutrition?
}

struct RecipeIngredient: Sendable, Equatable, Identifiable {
    let id: String
    /// The line as the clinician wrote it.
    let rawText: String
    /// For the WHOLE recipe, in `unitCode`.
    let qty: Double?
    let unitCode: String?
    let isToTaste: Bool
    let isOptional: Bool
    let prepNote: String?
}

/// The frozen per-serving nutrition of a recipe, with how much of it the ingredients could actually measure.
struct RecipeNutrition: Sendable, Equatable {
    let kcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    /// Nutrients with any data, out of `total` the catalogue tracks.
    let measured: Int
    let total: Int
    /// Nutrients whose data covers (nearly) every ingredient.
    let wellCovered: Int
}

// MARK: Groceries

/// `member_grocery_list`: the plan week's shopping, by aisle in store order. Derived on the server, never stored.
struct GroceryList: Sendable, Equatable {
    let planId: String?
    let periodStart: String?
    let periodEnd: String?
    let aisles: [GroceryAisle]
    /// The member's own lines (web).
    let custom: [GroceryCustomItem]

    static let empty = GroceryList(planId: nil, periodStart: nil, periodEnd: nil, aisles: [], custom: [])

    var isEmpty: Bool { aisles.isEmpty && custom.isEmpty }
}

struct GroceryAisle: Sendable, Equatable, Identifiable {
    let code: String
    let label: String
    let items: [GroceryItem]

    var id: String { code }
}

struct GroceryItem: Sendable, Equatable, Identifiable {
    let foodItemId: String
    let name: String
    let qty: Double?
    /// g or ml.
    let unit: String?
    let buyCount: Int?
    let buyUnit: String?
    let buyLabel: String?
    let approxPieces: Int?
    let staple: Bool
    let toTaste: Bool
    let approx: Bool
    /// The food now breaks one of the member's exclusions (an exclusion added after delivery).
    let excluded: Bool
    let uses: [GroceryUse]
    /// The prescribed recipes this line replaces after a swap.
    let insteadOf: [String]
    let checked: Bool
    /// "I already have this."
    let have: Bool

    var id: String { foodItemId }
}

struct GroceryUse: Sendable, Equatable {
    let date: String?
    let meal: String?
    let recipe: String?
}

struct GroceryCustomItem: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let qtyText: String?
    let aisleCode: String?
    let checked: Bool
}

/// What a tick is written against: a catalogue food, or one of the member's own lines.
enum GroceryTarget: Sendable, Equatable {
    case food(String)
    case custom(String)
}
