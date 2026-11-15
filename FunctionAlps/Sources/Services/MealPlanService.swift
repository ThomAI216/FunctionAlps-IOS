import Foundation

/// The clinician's meal plan for the member: read the days, "I ate this", swap, the recipe card, the grocery list.
/// Every rule that matters (what fits the member, what a swap does, how much to buy) is the server's; this is the seam.
struct MealPlanService: Sendable {
    private let backend: any FunctionAlpsBackend
    private let freshness: DataFreshness?

    init(backend: any FunctionAlpsBackend, freshness: DataFreshness? = nil) {
        self.backend = backend
        self.freshness = freshness
    }

    /// The plan from the member's today. An empty range = no delivered plan (the screens say so).
    func plan() async throws -> MealPlanRange { try await backend.mealPlan() }

    /// "I ate this": the server writes the meal log. Returns the log's id so the toast can undo it.
    func logPlanned(slotId: String, date: String) async throws -> PlannedMealLog {
        let result = try await backend.logPlannedMeal(slotId: slotId, planDate: date)
        if result.created { freshness?.homeChanged() }
        return result
    }

    func candidates(slotId: String, date: String, anyMeal: Bool) async throws -> [SwapCandidate] {
        try await backend.swapCandidates(slotId: slotId, planDate: date, anyMeal: anyMeal)
    }

    func swap(slotId: String, recipeId: String, date: String) async throws -> SwapOutcome {
        try await backend.swapPlannedMeal(slotId: slotId, recipeId: recipeId, planDate: date)
    }

    func recipe(id: String) async throws -> RecipeCard? { try await backend.recipeCard(id: id) }

    func groceries() async throws -> GroceryList { try await backend.groceryList() }

    func setChecked(patientId: String, list: GroceryList, target: GroceryTarget, checked: Bool) async throws {
        try await backend.setGroceryChecked(patientId: patientId, list: list, target: target, checked: checked)
    }
}
