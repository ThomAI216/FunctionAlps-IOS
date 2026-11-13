import Foundation
import Testing
@testable import FunctionAlps

/// The wire shapes of the menus programme's RPCs, from the documented contracts (`member_meal_plan`,
/// `member_swap_candidates`, `member_grocery_list`).
@Suite("Meal plan — decoding")
struct MealPlanDecodingTests {
    private let planJSON = """
    {"from":"2026-11-16","to":"2026-11-22",
     "plans":[{"id":"p1","title":"Gut reset","start_date":"2026-11-16","end_date":"2026-11-29","people":2,"show_calories":false,"allow_swaps":true}],
     "days":[{"date":"2026-11-16","plan_id":"p1","meals":[
       {"slot_id":"s1","moment_uid":"m1","moment":"breakfast","meal_type":"breakfast","note":"Fibre for your gut bacteria","portions":1.00,"servings":2,
        "swapped":false,"swap_kind":null,
        "recipe":{"id":"r1","title":"Warm lentil salad","slug":"warm-lentil-salad","prep_minutes":10,"cook_minutes":15,"servings":2},
        "excluded":false,"alternative_ids":["r9"],"logged_meal_id":null},
       {"slot_id":"s2","moment":"afternoon_snack","meal_type":"snack","swapped":true,"swap_kind":"variant",
        "recipe":{"id":"r2","title":"Hemp yoghurt","variant_kind":"higher_protein","kcal_per_serving":210.5,"own":true},
        "prescribed":{"id":"r3","title":"Yoghurt"},"excluded":true,"alternative_ids":[],"logged_meal_id":"log1"}]}]}
    """

    @Test func decodesThePlanRange() throws {
        let range = try JSON.decode(MealPlanWire.Plan.self, from: Data(planJSON.utf8)).model
        #expect(range.from == "2026-11-16")
        #expect(range.plans.first?.allowSwaps == true)
        let meals = try #require(range.days.first?.meals)
        #expect(meals.count == 2)
        #expect(meals[0].mealType == .breakfast)
        #expect(meals[0].note == "Fibre for your gut bacteria")
        #expect(meals[0].recipe.totalMinutes == 25)
        #expect(meals[0].alternativeIds == ["r9"])
        #expect(meals[0].isLogged == false)
        #expect(meals[1].mealType == .snack)
        #expect(meals[1].swapped && meals[1].swapKind == "variant")
        #expect(meals[1].prescribedTitle == "Yoghurt")
        #expect(meals[1].excluded)
        #expect(meals[1].isLogged)
        #expect(meals[1].recipe.own)
        #expect(meals[1].recipe.kcalPerServing == 210.5)
        #expect(meals[0].recipe.kcalPerServing == nil)   // calories only when the plan shows them
    }

    @Test func anEmptyPlanReadsAsNoDays() throws {
        let range = try JSON.decode(MealPlanWire.Plan.self, from: Data(#"{"from":"2026-11-16","to":"2026-11-22","plans":[],"days":[]}"#.utf8)).model
        #expect(range.isEmpty)
    }

    @Test func decodesSwapCandidatesAndTheTwoReplies() throws {
        let rows = try JSON.decode([MealPlanWire.CandidateRow].self, from: Data("""
        [{"recipe_id":"r1","title":"Salmon bowl","source":"alternative","variant_kind":null,"prep_minutes":10,"cook_minutes":20,"image_path":null,"is_current":false},
         {"recipe_id":"r2","title":"Quicker bowl","source":"variant","variant_kind":"quicker","prep_minutes":5,"cook_minutes":null,"image_path":null,"is_current":true},
         {"recipe_id":"r3","title":"Odd","source":"something_new","is_current":false}]
        """.utf8)).map(\.model)
        #expect(rows.map(\.source) == [.alternative, .variant, .library])
        #expect(rows[0].totalMinutes == 30)
        #expect(rows[1].isCurrent)
        let log = try JSON.decode(MealPlanWire.LogReply.self, from: Data(#"{"meal_log_id":"log9","created":false}"#.utf8)).model
        #expect(log == PlannedMealLog(mealLogId: "log9", created: false))
        let swap = try JSON.decode(MealPlanWire.SwapReply.self, from: Data(#"{"changed":true,"swap_id":4,"slot_id":"s1","plan_date":"2026-11-16","recipe_id":"r2","kind":"swap"}"#.utf8)).model
        #expect(swap == SwapOutcome(changed: true, recipeId: "r2", kind: "swap"))
    }

    @Test func decodesTheGroceryList() throws {
        let list = try JSON.decode(MealPlanWire.Grocery.self, from: Data("""
        {"plan_id":"p1","period_start":"2026-11-16","period_end":"2026-11-22","people":2,
         "aisles":[{"code":"produce","label":"Fruit & vegetables","items":[
            {"food_item_id":"f1","name":"Cherry tomatoes","qty":400,"unit":"g","staple":false,"to_taste":false,"approx":false,"excluded":false,
             "for":[{"date":"2026-11-17","meal":"dinner","moment":"dinner","recipe":"Lentil salad"}],"checked":true,"have":false},
            {"food_item_id":"f2","name":"Tamari","buy":{"count":1,"unit":"bottle","label":"bottle (500 ml)"},"approx_pieces":null,
             "instead_of":["Soy sauce"],"checked":false,"have":true}]}],
         "custom":[{"id":"c1","label":"Dish soap","qty_text":"2","checked":false}]}
        """.utf8)).model
        #expect(list.planId == "p1")
        let items = try #require(list.aisles.first?.items)
        #expect(items[0].checked && items[0].uses.first?.recipe == "Lentil salad")
        #expect(items[1].buyCount == 1 && items[1].buyLabel == "bottle (500 ml)")
        #expect(items[1].insteadOf == ["Soy sauce"])
        #expect(items[1].have)
        #expect(list.custom.first?.qtyText == "2")
    }

    @Test func decodesARecipeWithOddJsonbShapes() throws {
        let recipe = try JSON.decode(MealPlanWire.Recipe.self, from: Data("""
        {"id":"r1","title":"Lentil salad","body_md":"## Preparation\\n1. Rinse.","steps":["Mix", {"text":"Serve"}, 5],"servings":2,"prep_minutes":10,"cook_minutes":null,
         "yield_text":null,"variant_kind":null,
         "computed_nutrition":{"kcal":412,"protein_g":24.1,"carbs_g":50,"fat_g":12,"fiber_g":14,
            "micros":{"vitamin_c_mg":12.5,"zinc_mg":null},
            "coverage":{"vitamin_c_mg":1,"zinc_mg":0,"iron_mg":0.5,"magnesium_mg":0.97}}}
        """.utf8))
        let card = recipe.model(ingredients: [])
        #expect(card.steps == ["Mix", "Serve"])
        let n = try #require(card.nutrition)
        #expect(n.proteinG == 24.1)
        #expect(n.total == 4)
        #expect(n.measured == 3)
        #expect(n.wellCovered == 2)
        let bare = try JSON.decode(MealPlanWire.Recipe.self, from: Data(#"{"id":"r2","steps":"not an array","computed_nutrition":"x"}"#.utf8)).model(ingredients: [])
        #expect(bare.steps.isEmpty && bare.nutrition == nil)
    }
}
