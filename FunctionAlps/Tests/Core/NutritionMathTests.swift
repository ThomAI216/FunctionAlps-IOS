import Foundation
import Testing
@testable import FunctionAlps

@Suite("Nutrition maths — the Expo tdee / macros / repartition helpers, line for line")
struct NutritionMathTests {
    @Test("TDEE: Harris-Benedict × the activity factor, Katch-McArdle when a body-fat is known")
    func tdee() {
        // 72 kg · 175 cm · 34 y · male · moderately active: BMR 1699.75 → ×1.55 → 2635
        #expect(NutritionMath.tdee(weightKg: 72, heightCm: 175, age: 34, sex: .male, activity: .moderatelyActive, bodyFatPercent: nil) == 2635)
        // With 18 % body-fat: LBM 59.04 → 370 + 21.6 × 59.04 = 1645.26 → ×1.55 → 2550
        #expect(NutritionMath.tdee(weightKg: 72, heightCm: 175, age: 34, sex: .male, activity: .moderatelyActive, bodyFatPercent: 18) == 2550)
        #expect(NutritionMath.tdee(weightKg: 60, heightCm: 165, age: 30, sex: .female, activity: .sedentary, bodyFatPercent: nil) == Int(((447.593 + 9.247 * 60 + 3.098 * 165 - 4.33 * 30) * 1.2).rounded()))
    }

    @Test("Goal macros: protein per kg by sex, fat 40 %, carbs the remainder, offset by body-fat band")
    func goalMacros() {
        let t = NutritionMath.goalMacros(tdee: 2635, weightKg: 72, sex: .male, goal: .cut, bodyFatPercent: nil)
        // bf defaults to 22 → cut offset −400 → 2235 kcal; protein 130 g; fat 99 g; carbs (2235 − 520 − 894) / 4 = 205
        #expect(t.calories == 2235)
        #expect(t.proteinG == 130)
        #expect(t.fatG == 99)
        #expect(t.carbsG == 205)
        #expect(NutritionMath.goalOffset(goal: .build, bodyFatPercent: 15) == 300)
        #expect(NutritionMath.goalOffset(goal: .cut, bodyFatPercent: 30) == -500)
        #expect(NutritionMath.goalOffset(goal: .maintain, bodyFatPercent: 30) == 0)
        #expect(NutritionMath.goalMacros(tdee: 1200, weightKg: 120, sex: .male, goal: .cut, bodyFatPercent: 40).carbsG == 0)
    }

    @Test("Goal from health goals, fibre target, offset warnings")
    func helpers() {
        #expect(NutritionMath.goal(fromHealthGoals: ["build_muscle"]) == .build)
        #expect(NutritionMath.goal(fromHealthGoals: ["lose_weight"]) == .cut)
        #expect(NutritionMath.goal(fromHealthGoals: ["sleep"]) == .maintain)
        #expect(NutritionMath.fiberTarget(calories: 1500) == 25)
        #expect(NutritionMath.fiberTarget(calories: 2500) == 35)
        #expect(NutritionMath.offsetWarning(offset: 0, goal: .maintain, bodyFatPercent: 22) == nil)
        #expect(NutritionMath.offsetWarning(offset: -700, goal: .cut, bodyFatPercent: 22)?.tone == .caution)
        #expect(NutritionMath.offsetWarning(offset: -550, goal: .cut, bodyFatPercent: 30)?.tone == .ok)
        #expect(NutritionMath.offsetWarning(offset: 600, goal: .build, bodyFatPercent: 22)?.tone == .caution)
    }

    @Test("Repartition: largest-remainder split that always sums to the targets")
    func repartition() {
        let targets = NutritionMath.MacroTargets(proteinG: 130, carbsG: 205, fatG: 99, calories: 2235)
        let plan = NutritionMath.repartitionPlan(meals: 3, snacks: 2, targets: targets)
        #expect(plan.count == 5)
        #expect(plan.map(\.protein).reduce(0, +) == 130)
        #expect(plan.map(\.carbs).reduce(0, +) == 205)
        #expect(plan.map(\.fat).reduce(0, +) == 99)
        #expect(plan[0].kind == .breakfast && plan[4].kind == .eveningSnack)
        #expect(NutritionMath.mealSlots(5).count == 5)
        #expect(NutritionMath.snackSlots(3).count == 3)
        #expect(NutritionMath.distribute(10, ratios: [0, 0]) == [5, 5])
        #expect(NutritionMath.distribute(7, ratios: [1, 1, 1]) == [3, 2, 2])
    }

    @Test("The catalogue's RDA values are the coverage table's")
    func catalogueMatchesCoverage() {
        for n in NutrientCatalog.nutrients {
            let c = MicroCoverage.nutrients.first { $0.key == n.key }
            #expect(c != nil, "\(n.key) missing from MicroCoverage")
            #expect(c?.rdaMale == n.rdaMale && c?.rdaFemale == n.rdaFemale, "\(n.key) RDA drift")
        }
        #expect(NutrientCatalog.nutrients.count == 21)
        #expect(NutrientCatalog.nutrients(in: .fattyAcids).count == 5)
        #expect(NutrientCatalog.elements["magnesium"]?.symbol == "Mg")
        #expect(NutrientCatalog.symptomLabel("brain_fog") == "Brain fog")
    }

    @Test("Coverage helpers and the per-meal nutrient score")
    func coverage() {
        #expect(NutritionMath.coveragePercent(consumed: 30, target: 90) == 33)
        #expect(NutritionMath.coveragePercent(consumed: 120, target: 90) == 133)
        let consumed: [String: Double] = ["vitamin_c": 90, "vitamin_d3": 25]
        // Vitamins group: 8 nutrients, C 100 % + D3 50 % → 150 / 8 = 18.75 → 19
        #expect(NutritionMath.groupCoverage(.vitamins, sex: .male, consumed: consumed) == 19)
        let gaps = NutritionMath.gaps(threshold: 0.7, sex: .male, limit: 3, consumed: consumed)
        #expect(gaps.count == 3 && gaps.allSatisfy { $0.pct < 0.7 } && gaps[0].pct <= gaps[1].pct)
        #expect(NutritionMath.gaps(threshold: 0.7, sex: .male, limit: 99, consumed: consumed).count == 20)
    }

    @Test("The targets write: explicit nulls for cleared counts, targets only when customised")
    func write() throws {
        var w = NutritionProfileWrite(appSex: "male", appAge: 34, appHeightCm: 175, appWeightKg: 72, estimatedBodyFatPercent: nil, activityLevel: "moderately_active", goalMode: "cut", macrosCustomized: false, mealsPerDay: nil, snacksPerDay: 1, customCalorieOffsetKcal: -350, targetCalories: 2000, targetProteinG: 130, targetCarbsG: 200, targetFatG: 90, tdeeKcal: 2635)
        let enc = JSONEncoder(); enc.keyEncodingStrategy = .convertToSnakeCase
        var json = String(decoding: try enc.encode(w), as: UTF8.self)
        #expect(json.contains("\"meals_per_day\":null"))
        #expect(json.contains("\"snacks_per_day\":1"))
        #expect(json.contains("\"custom_calorie_offset_kcal\":-350"))
        #expect(!json.contains("estimated_body_fat_percent"))
        #expect(!json.contains("target_protein_g"))
        w.macrosCustomized = true
        json = String(decoding: try enc.encode(w), as: UTF8.self)
        #expect(json.contains("\"target_protein_g\":130") && json.contains("\"tdee_kcal\":2635"))
    }
}
