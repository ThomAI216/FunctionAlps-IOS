import Foundation
import Testing
@testable import FunctionAlps

struct MicroCoverageTests {
    @Test func coverageIsCappedPerNutrientAndAveraged() {
        // 21 nutrients; vitamin C at 300 % counts as 100 %, everything else 0 → 100/21 ≈ 5.
        let meal = MealLog(id: "m", loggedAt: Date(), micros: ["vitamin_c_mg": 225])
        #expect(MicroCoverage.overall(meals: [meal], sex: .female) == 5)
        // Male target is 90 mg: 225/90 still capped → same 5.
        #expect(MicroCoverage.overall(meals: [meal], sex: .male) == 5)
    }

    @Test func noMicrosMeansNoData() {
        let meal = MealLog(id: "m", loggedAt: Date(), totalCalories: 500)
        #expect(MicroCoverage.overall(meals: [meal], sex: nil) == nil)
        #expect(MicroCoverage.overall(meals: [], sex: nil) == nil)
    }

    @Test func sexPicksTheTarget() {
        // Iron: 18 mg for women, 8 mg for men. 9 mg → 50 % vs 100 % on that nutrient.
        let meal = MealLog(id: "m", loggedAt: Date(), micros: ["iron_mg": 9])
        let female = MicroCoverage.overall(meals: [meal], sex: .female)!
        let male = MicroCoverage.overall(meals: [meal], sex: .male)!
        #expect(male > female)
        #expect(female == Int((0.5 / 21 * 100).rounded()))
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
