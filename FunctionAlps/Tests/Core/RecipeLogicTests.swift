import Foundation
import Testing
@testable import FunctionAlps

private let en = Locale(identifier: "en_US")

private func line(_ raw: String, qty: Double? = nil, unit: String? = nil, toTaste: Bool = false) -> RecipeIngredient {
    RecipeIngredient(id: raw, rawText: raw, qty: qty, unitCode: unit, isToTaste: toTaste, isOptional: false, prepNote: nil)
}

private func plannedMeal(swapped: Bool = false, kind: String? = nil, prescribed: String? = nil, servings: Double? = 2) -> PlannedMeal {
    PlannedMeal(slotId: "s", momentUid: nil, moment: nil, mealType: .dinner, note: nil, portions: 1, servings: servings, swapped: swapped,
                swapKind: kind, recipe: PlannedRecipe(id: "cur", title: "Now", slug: nil, imagePath: nil, prepMinutes: nil, cookMinutes: nil,
                                                       servings: 4, variantKind: nil, own: false, kcalPerServing: nil),
                prescribedId: prescribed, prescribedTitle: nil, excluded: false, alternativeIds: [], loggedMealId: nil)
}

private func candidate(_ id: String, _ source: SwapCandidate.Source, kind: String? = nil, current: Bool = false) -> SwapCandidate {
    SwapCandidate(recipeId: id, title: "Title \(id)", source: source, variantKind: kind, prepMinutes: nil, cookMinutes: nil, imagePath: nil, isCurrent: current)
}

@Suite("Recipe logic")
struct RecipeLogicTests {
    @Test func servingsScaleTheWholeRecipeAmounts() {
        #expect(RecipeLogic.scaled(200, recipeServings: 4, chosen: 2) == 100)
        #expect(RecipeLogic.scaled(200, recipeServings: nil, chosen: 3) == 600)
    }

    @Test func stepperOpensOnThePortionsCookedAndStaysInRange() {
        #expect(RecipeLogic.defaultServings(meal: plannedMeal(servings: 2), recipe: nil) == 2)
        #expect(RecipeLogic.defaultServings(meal: plannedMeal(servings: nil), recipe: nil) == 4)
        #expect(RecipeLogic.defaultServings(meal: plannedMeal(servings: 40), recipe: nil) == 12)
        #expect(RecipeLogic.defaultServings(meal: nil, recipe: nil) == 1)
    }

    @Test func amountsReadLikeACookbook() {
        #expect(RecipeLogic.amountText(0.5, unit: "tbsp", locale: en) == "½")
        #expect(RecipeLogic.amountText(1.5, unit: "cup", locale: en) == "1½")
        #expect(RecipeLogic.amountText(0.25, unit: "bunch", locale: en) == "¼")
        #expect(RecipeLogic.amountText(2, unit: "tbsp", locale: en) == "2")
        #expect(RecipeLogic.amountText(2.2, unit: "tbsp", locale: en) == "2.2")
        #expect(RecipeLogic.amountText(123.4, unit: "g", locale: en) == "123")
        #expect(RecipeLogic.amountText(2.46, unit: "g", locale: en) == "2.5")
    }

    @Test func quantityColumnFollowsTheStepper() {
        let l = line("Green lentils", qty: 160, unit: "g")
        #expect(RecipeLogic.quantityLabel(l, recipeServings: 4, chosen: 2, locale: en) == "80 g")
        #expect(RecipeLogic.quantityLabel(l, recipeServings: 4, chosen: 4, locale: en) == "160 g")
        #expect(RecipeLogic.quantityLabel(line("Salt", toTaste: true), recipeServings: 4, chosen: 4, locale: en) == "to taste")
        #expect(RecipeLogic.quantityLabel(line("Lemon", qty: 1, unit: nil), recipeServings: 4, chosen: 2, locale: en) == "½")
        #expect(RecipeLogic.quantityLabel(line("Olive oil", qty: 4, unit: "tbsp"), recipeServings: 4, chosen: 2, locale: en) == "2 tbsp")
    }

    @Test func nameDropsAnAmountThatHasItsOwnColumn() {
        #expect(RecipeLogic.ingredientName(line("200 g green lentils", qty: 200, unit: "g")) == "green lentils")
        #expect(RecipeLogic.ingredientName(line("2 tbsp olive oil", qty: 2, unit: "tbsp")) == "olive oil")
        #expect(RecipeLogic.ingredientName(line("1 lemon", qty: 1, unit: nil)) == "lemon")
        #expect(RecipeLogic.ingredientName(line("Green lentils", qty: 200, unit: "g")) == "Green lentils")
        #expect(RecipeLogic.ingredientName(line("200 g green lentils", qty: nil, unit: nil)) == "200 g green lentils")
        #expect(RecipeLogic.ingredientName(line("3", qty: 3, unit: nil)) == "3")
    }

    @Test func methodSplitsOnEachStepsPhase() {
        let m = RecipeLogic.method(steps: [
            RecipeStep(phase: .prep, text: "Rinse the lentils."), RecipeStep(phase: .cook, text: "Simmer for 20 minutes."),
            RecipeStep(phase: .prep, text: "Chop the herbs."), RecipeStep(phase: .cook, text: "Toss with lemon."),
        ])
        #expect(m.preparation == ["Rinse the lentils.", "Chop the herbs."])
        #expect(m.cooking == ["Simmer for 20 minutes.", "Toss with lemon."])
        #expect(m.plain.isEmpty)
        #expect(m.isSplit)
    }

    @Test func plainStringStepsAreOneList() {
        let m = RecipeLogic.method(steps: [RecipeStep(phase: nil, text: "Mix."), RecipeStep(phase: nil, text: "Bake.")])
        #expect(m.plain == ["Mix.", "Bake."])
        #expect(!m.isSplit)
        #expect(m.all == ["Mix.", "Bake."])
        #expect(RecipeLogic.method(steps: []).isEmpty)
    }

    @Test func aSingleSidedRecipeIsNotSplit() {
        let m = RecipeLogic.method(steps: [RecipeStep(phase: .cook, text: "Roast.")])
        #expect(!m.isSplit)
        #expect(m.all == ["Roast."])
    }

    @Test func makeItListsOnlyVersionsNotTheOneInForce() {
        let meal = plannedMeal()
        let options = RecipeLogic.versions(candidates: [
            candidate("v1", .variant, kind: "higher_protein"), candidate("lib", .library),
            candidate("v2", .variant, kind: "quicker"), candidate("cur", .variant, kind: "x", current: true),
        ], meal: meal)
        #expect(options.map(\.recipeId) == ["v1", "v2"])
        #expect(options.map(\.label) == ["Higher protein", "Quicker"])
    }

    @Test func aVersionInForceOffersTheOriginalBack() {
        let meal = plannedMeal(swapped: true, kind: "variant", prescribed: "orig")
        let options = RecipeLogic.versions(candidates: [candidate("v2", .variant, kind: "quicker")], meal: meal)
        #expect(options.map(\.recipeId) == ["orig", "v2"])
        #expect(RecipeLogic.versions(candidates: [], meal: plannedMeal(swapped: true, kind: "swap", prescribed: "orig")).isEmpty)
    }
}
