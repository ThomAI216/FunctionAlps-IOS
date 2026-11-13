import Foundation
import Testing
@testable import FunctionAlps

struct MicroCoverageTests {
    @Test func coverageIsCappedPerNutrientAndAveragedOverNutrientsWithData() {
        // Only vitamin C has a value: 300 % is capped to 100 %, and it is the only nutrient averaged (1 of 21).
        let meal = MealLog(id: "m", loggedAt: Date(), micros: ["vitamin_c_mg": 225])
        #expect(MicroCoverage.overall(meals: [meal], sex: .female) == 100)
        #expect(MicroCoverage.overall(meals: [meal], sex: .male) == 100)
        let d = MicroCoverage.overallDetail(meals: [meal], sex: .female)
        #expect(d == MicroCoverage.Overall(percent: 100, included: 1, total: 21))
    }

    @Test func aNutrientWithNoDataIsLeftOutNotCountedAsZero() {
        // Vitamin C at 100 % and iron at 50 % (female 18 mg): mean 75 over 2, not 75 * 2 / 21.
        let meal = MealLog(id: "m", loggedAt: Date(), micros: ["vitamin_c_mg": 75, "iron_mg": 9])
        let d = MicroCoverage.overallDetail(meals: [meal], sex: .female)
        #expect(d == MicroCoverage.Overall(percent: 75, included: 2, total: 21))
    }

    @Test func aRealZeroStillCounts() {
        let meal = MealLog(id: "m", loggedAt: Date(), micros: ["vitamin_c_mg": 75, "iron_mg": 0])
        let d = MicroCoverage.overallDetail(meals: [meal], sex: .female)
        #expect(d == MicroCoverage.Overall(percent: 50, included: 2, total: 21))
    }

    @Test func aNutrientPresentInSomeMealsCountsOnItsSum() {
        let a = MealLog(id: "a", loggedAt: Date(), micros: ["iron_mg": 9])
        let b = MealLog(id: "b", loggedAt: Date(), micros: ["zinc_mg": 8])
        let d = MicroCoverage.overallDetail(meals: [a, b], sex: .female)
        // iron 9/18 = 0.5, zinc 8/8 = 1 → 75 over 2 nutrients.
        #expect(d == MicroCoverage.Overall(percent: 75, included: 2, total: 21))
    }

    @Test func noMicrosMeansNoData() {
        let meal = MealLog(id: "m", loggedAt: Date(), totalCalories: 500)
        #expect(MicroCoverage.overall(meals: [meal], sex: nil) == nil)
        #expect(MicroCoverage.overall(meals: [], sex: nil) == nil)
        #expect(MicroCoverage.overallDetail(meals: [], sex: nil) == nil)
        // A key outside the 21 tracked nutrients (sugar) is not a nutrient with data here.
        let sugarOnly = MealLog(id: "s", loggedAt: Date(), micros: ["sugar_g": 12])
        #expect(MicroCoverage.overallDetail(meals: [sugarOnly], sex: nil) == nil)
    }

    @Test func sexPicksTheTarget() {
        // Iron: 18 mg for women, 8 mg for men. 9 mg → 50 % vs 100 % on that nutrient (the only one with data).
        let meal = MealLog(id: "m", loggedAt: Date(), micros: ["iron_mg": 9])
        #expect(MicroCoverage.overall(meals: [meal], sex: .female) == 50)
        #expect(MicroCoverage.overall(meals: [meal], sex: .male) == 100)
    }

    @Test func mealNutrientScoreAveragesOverNutrientsWithDataAndSaysHowMany() {
        // 75 % over two nutrients, a meal that is one of 3 expected today: 75 / (1/3) = 225, capped at 100.
        let meal = MealLog(id: "m", loggedAt: Date(), micros: ["vitamin_c_mg": 75, "iron_mg": 9])
        let s = NutritionMath.mealNutrientScore(meal, sex: .female, mealsToday: 3)
        #expect(s == NutritionMath.MealNutrientScore(score: 100, included: 2, total: 21))
        // One meal of 2 with iron 4.5 mg (25 % of 18) alone: 25 / (1/2) = 50.
        let small = MealLog(id: "n", loggedAt: Date(), micros: ["iron_mg": 4.5])
        #expect(NutritionMath.mealNutrientScore(small, sex: .female, mealsToday: 2) == NutritionMath.MealNutrientScore(score: 50, included: 1, total: 21))
    }

    @Test func mealWithoutNutrientDataHasNoScore() {
        let meal = MealLog(id: "m", loggedAt: Date(), totalCalories: 500)
        #expect(NutritionMath.mealNutrientScore(meal, sex: .female, mealsToday: 2) == nil)
    }

    @Test func macroProximityNeedsAllThreeTargets() {
        #expect(MicroCoverage.macroProximity(protein: 60, carbs: 100, fat: 40, targetProtein: 120, targetCarbs: 200, targetFat: 80) == 50)
        #expect(MicroCoverage.macroProximity(protein: 200, carbs: 300, fat: 100, targetProtein: 120, targetCarbs: 200, targetFat: 80) == 100)
        #expect(MicroCoverage.macroProximity(protein: 60, carbs: 100, fat: 40, targetProtein: nil, targetCarbs: 200, targetFat: 80) == nil)
    }

    @Test func relogSourceCopiesTheMeal() {
        let meal = MealLog(id: "m", loggedAt: Date(), mealType: .lunch, name: "Bowl", totalCalories: 420, items: [MealItem(name: "rice")], scores: MealScores(inflammation: 1, glycemic: 2, digestion: 3), micros: ["iron_mg": 2])
        let src = RelogSource(meal: meal)
        #expect(src.name == "Bowl" && src.mealType == .lunch && src.kcal == 420 && src.items.count == 1 && src.scores?.digestion == 3 && src.micros["iron_mg"] == 2)
    }
}
