import Foundation
import Testing
@testable import FunctionAlps

struct MicroPresenceTests {
    private func meal(_ id: String, micros: [String: Double], coverage: MealMicroCoverage? = nil, status: MealLog.AnalysisStatus? = nil) -> MealLog {
        MealLog(id: id, loggedAt: Date(), analysisStatus: status, micros: micros, microCoverage: coverage)
    }

    @Test("The Swift key list matches the server's 34 catalogue keys and includes every tracked nutrient's field")
    func keyList() {
        #expect(MicroPresence.catalogueKeys.count == 34)
        #expect(Set(MicroPresence.catalogueKeys).count == 34)
        for n in MicroCoverage.nutrients {
            #expect(MicroPresence.catalogueKeys.contains(n.field), "\(n.field) missing")
        }
    }

    @Test("No value in any meal is no data, not zero; no meals is no data too")
    func noData() {
        #expect(MicroPresence.status(field: "iron_mg", meals: []) == .noData)
        #expect(MicroPresence.status(field: "iron_mg", meals: [meal("a", micros: ["zinc_mg": 2]), meal("b", micros: [:])]) == .noData)
    }

    @Test("A value on every meal is measured; a real zero still counts as a value")
    func measured() {
        let meals = [meal("a", micros: ["iron_mg": 2]), meal("b", micros: ["iron_mg": 0])]
        #expect(MicroPresence.status(field: "iron_mg", meals: meals) == .measured)
    }

    @Test("A value on some meals is partial with the meal counts")
    func partial() {
        let meals = [meal("a", micros: ["iron_mg": 2]), meal("b", micros: ["iron_mg": 1]), meal("c", micros: ["zinc_mg": 1])]
        #expect(MicroPresence.status(field: "iron_mg", meals: meals) == .partial(mealsWithValue: 2, totalMeals: 3))
    }

    @Test("A meal still being analysed is not counted")
    func pendingMealIgnored() {
        let meals = [meal("a", micros: ["iron_mg": 2]), meal("b", micros: [:], status: .pricing)]
        #expect(MicroPresence.status(field: "iron_mg", meals: meals) == .measured)
    }

    @Test("When the meal's micro_coverage lists the key as partial, the status says some foods are missing")
    func coveragePartialUsed() {
        let cov = MealMicroCoverage(tracked: 34, measured: 30, items: 3, itemsFromCatalogue: 2, partial: ["iron_mg"])
        let meals = [meal("a", micros: ["iron_mg": 2], coverage: cov), meal("b", micros: ["iron_mg": 1])]
        #expect(MicroPresence.status(field: "iron_mg", meals: meals) == .someFoodsMissing)
        // Without micro_coverage the same meals fall back to key presence: measured.
        let plain = [meal("a", micros: ["iron_mg": 2]), meal("b", micros: ["iron_mg": 1])]
        #expect(MicroPresence.status(field: "iron_mg", meals: plain) == .measured)
        // Meals-with-value partial wins over the foods note.
        let mixed = [meal("a", micros: ["iron_mg": 2], coverage: cov), meal("b", micros: [:])]
        #expect(MicroPresence.status(field: "iron_mg", meals: mixed) == .partial(mealsWithValue: 1, totalMeals: 2))
    }

    @Test("Notes: sparse nutrients without a value say they are not in the food data; partial says from N of M meals")
    func notes() {
        #expect(MicroPresence.note(status: .noData, field: "biotin_mcg") == .notInFoodData)
        #expect(MicroPresence.note(status: .noData, field: "chromium_mcg") == .notInFoodData)
        #expect(MicroPresence.note(status: .noData, field: "vitamin_k2_mcg") == .notInFoodData)
        #expect(MicroPresence.note(status: .noData, field: "iron_mg") == nil)
        #expect(MicroPresence.note(status: .measured, field: "biotin_mcg") == nil)
        #expect(MicroPresence.note(status: .partial(mealsWithValue: 2, totalMeals: 3), field: "iron_mg") == .fromMeals(2, of: 3))
        #expect(MicroPresence.note(status: .someFoodsMissing, field: "iron_mg") == .someFoodsMissing)
    }

    @Test("Statuses are keyed by the tracked nutrient's key")
    func statusesByKey() {
        let s = MicroPresence.statuses(meals: [meal("a", micros: ["vitamin_c_mg": 10])])
        #expect(s["vitamin_c"] == .measured)
        #expect(s["iron"] == .noData)
        #expect(s.count == MicroCoverage.nutrients.count)
    }

    @Test("Summary: one meal with micro_coverage uses it; otherwise key counts over the catalogue keys only")
    func summary() {
        let cov = MealMicroCoverage(tracked: 34, measured: 28, items: 2, itemsFromCatalogue: 2, partial: [])
        #expect(MicroPresence.summary(meals: [meal("a", micros: ["iron_mg": 1], coverage: cov)]) == MicroPresence.Summary(measured: 28, tracked: 34))
        let two = [meal("a", micros: ["iron_mg": 1, "fiber_g": 3]), meal("b", micros: ["zinc_mg": 1, "iron_mg": 2])]
        #expect(MicroPresence.summary(meals: two) == MicroPresence.Summary(measured: 2, tracked: 34))
        #expect(MicroPresence.summary(meals: [meal("a", micros: [:])]) == nil)
        #expect(MicroPresence.summary(meals: []) == nil)
    }

    @Test("Gaps leave out nutrients with no data")
    func gapsSkipNoData() {
        let all = NutritionMath.gaps(threshold: 0.7, sex: .female, limit: 99, consumed: [:])
        #expect(all.count == 21)
        let some = NutritionMath.gaps(threshold: 0.7, sex: .female, limit: 99, consumed: [:], available: ["iron", "zinc"])
        #expect(some.map(\.nutrient.key).sorted() == ["iron", "zinc"])
        #expect(NutritionMath.gaps(threshold: 0.7, sex: .female, limit: 99, consumed: [:], available: []).isEmpty)
    }
}
