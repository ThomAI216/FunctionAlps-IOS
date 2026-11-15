import Foundation
import Testing
@testable import FunctionAlps

private let exampleJSON = """
{"example":true,"slug":"foundational-week","nominal_dates":true,"from":"2001-01-01","to":"2001-01-07",
 "plans":[{"id":"ex1","title":"Foundational week","description":"A reference week","start_date":"2001-01-01","end_date":"2001-01-07",
           "people":1,"show_calories":false,"allow_swaps":false,"example":true}],
 "days":[{"date":"2001-01-01","day_index":0,"plan_id":"ex1","meals":[
   {"slot_id":"a","moment_uid":"breakfast","moment":"breakfast","meal_type":"breakfast","option_label":null,"note":null,"portions":1.00,"servings":1.00,
    "swapped":false,"swap_kind":null,
    "recipe":{"id":"r1","title":"Plain yogurt, berries, walnuts","slug":"yogurt-berries","prep_minutes":5,"cook_minutes":0,"servings":1,
              "image_path":"https://members.functionalps.ch/recipes/foundational/yogurt-berries.jpg"},
    "excluded":false,"alternative_ids":[],"logged_meal_id":null},
   {"slot_id":"b","moment_uid":"snack","moment":"snack","meal_type":"snack","option_label":"High-protein","portions":1.00,"servings":1.00,
    "swapped":false,"recipe":{"id":"r2","title":"Warm edamame with lemon and sesame","slug":"edamame"},"excluded":false,"alternative_ids":[],"logged_meal_id":null},
   {"slot_id":"c","moment_uid":"snack","moment":"snack","meal_type":"snack","option_label":"Complex carb","portions":1.00,"servings":1.00,
    "swapped":false,"recipe":{"id":"r3","title":"Apple, almond butter","slug":"apple-almond"},"excluded":false,"alternative_ids":[],"logged_meal_id":null}]}]}
"""

private func meal(_ id: String, _ type: MealLog.MealType, option: String? = nil) -> PlannedMeal {
    PlannedMeal(
        slotId: id, momentUid: nil, moment: nil, mealType: type, note: nil, portions: 1, servings: 1, swapped: false, swapKind: nil,
        recipe: PlannedRecipe(id: "r-\(id)", title: "Recipe \(id)", slug: nil, imagePath: nil, prepMinutes: nil, cookMinutes: nil,
                              servings: 1, variantKind: nil, own: false, kcalPerServing: nil),
        prescribedId: nil, prescribedTitle: nil, excluded: false, alternativeIds: [], loggedMealId: nil, optionLabel: option
    )
}

@Suite("Foundational week")
struct FoundationalWeekTests {
    // MARK: Decoding

    @Test func decodesTheExampleWeekWithItsFlagAndTheTwoSnackOptions() throws {
        let range = try JSON.decode(MealPlanWire.Plan.self, from: Data(exampleJSON.utf8)).model
        #expect(range.example)
        #expect(range.from == "2001-01-01")
        #expect(range.plans.first?.allowSwaps == false)
        let meals = try #require(range.days.first?.meals)
        #expect(meals.count == 3)
        #expect(meals[0].optionLabel == nil)
        #expect(meals[1].mealType == .snack && meals[1].optionLabel == "High-protein")
        #expect(meals[2].mealType == .snack && meals[2].optionLabel == "Complex carb")
        #expect(meals[0].recipe.imagePath == "https://members.functionalps.ch/recipes/foundational/yogurt-berries.jpg")
    }

    @Test func anOrdinaryPlanIsNotAnExample() throws {
        let range = try JSON.decode(MealPlanWire.Plan.self, from: Data(#"{"from":"2026-11-16","to":"2026-11-22","plans":[],"days":[]}"#.utf8)).model
        #expect(range.example == false)
    }

    @Test func decodesTheExampleGroceriesFlag() throws {
        let list = try JSON.decode(MealPlanWire.Grocery.self, from: Data(#"{"example":true,"plan_id":"ex1","period_start":"2001-01-01","period_end":"2001-01-07","people":1,"aisles":[],"custom":[]}"#.utf8)).model
        #expect(list.example)
        #expect(list.planId == "ex1")
        let own = try JSON.decode(MealPlanWire.Grocery.self, from: Data(#"{"plan_id":"p1","aisles":[],"custom":[]}"#.utf8)).model
        #expect(own.example == false)
    }

    @Test func aLocalTickKeepsTheExampleFlag() {
        let item = GroceryItem(foodItemId: "f1", name: "Oats", qty: nil, unit: nil, buyCount: nil, buyUnit: nil, buyLabel: nil, approxPieces: nil,
                               staple: false, toTaste: false, approx: false, excluded: false, uses: [], insteadOf: [], checked: false, have: false)
        let list = GroceryList(planId: "ex1", periodStart: nil, periodEnd: nil, aisles: [GroceryAisle(code: "a", label: "Grains", items: [item])], custom: [], example: true)
        let ticked = GroceryLogic.setting(.food("f1"), checked: true, in: list)
        #expect(ticked.example)
        #expect(ticked.aisles.first?.items.first?.checked == true)
    }

    // MARK: Who sees what

    @Test func noDeliveredPlanShowsTheExampleOnPlanAndGroceries() {
        #expect(FoundationalWeek.placement(hasDeliveredPlan: false) == .replacesPlan)
    }

    @Test func aDeliveredPlanKeepsTheMembersOwnPlanAndOnlyOffersTheEntry() {
        #expect(FoundationalWeek.placement(hasDeliveredPlan: true) == .entryOnly)
    }

    @Test func anUnknownAnswerNeverHidesAMembersOwnPlan() {
        #expect(FoundationalWeek.placement(hasDeliveredPlan: nil) == .entryOnly)
    }

    // MARK: Photos

    @Test func onlyHttpsPhotosAreLoaded() {
        let good = "https://members.functionalps.ch/recipes/foundational/x.jpg"
        #expect(FoundationalWeek.imageURL(good)?.absoluteString == good)
        #expect(FoundationalWeek.imageURL("  \(good) ")?.absoluteString == good)
        #expect(FoundationalWeek.imageURL("http://members.functionalps.ch/x.jpg") == nil)
        #expect(FoundationalWeek.imageURL("HTTP://members.functionalps.ch/x.jpg") == nil)
        #expect(FoundationalWeek.imageURL("file:///private/x.jpg") == nil)
        #expect(FoundationalWeek.imageURL("data:image/png;base64,AAAA") == nil)
        #expect(FoundationalWeek.imageURL("javascript:alert(1)") == nil)
        #expect(FoundationalWeek.imageURL("//members.functionalps.ch/x.jpg") == nil)
        #expect(FoundationalWeek.imageURL("recipes/foundational/x.jpg") == nil)   // a storage path, not a URL
        #expect(FoundationalWeek.imageURL("https://") == nil)
        #expect(FoundationalWeek.imageURL("") == nil)
        #expect(FoundationalWeek.imageURL(nil) == nil)
    }

    @Test func anHttpsSchemeIsAcceptedInAnyCase() {
        #expect(FoundationalWeek.imageURL("HTTPS://members.functionalps.ch/x.jpg") != nil)
    }

    // MARK: Snack group

    @Test func theTwoSnackOptionsFoldIntoOneGroupInPlace() {
        let day = [meal("b", .breakfast), meal("l", .lunch), meal("s1", .snack, option: "High-protein"),
                   meal("s2", .snack, option: "Complex carb"), meal("d", .dinner)]
        let groups = FoundationalWeek.groups(day)
        #expect(groups.count == 4)
        #expect(groups[0] == .single(day[0]))
        #expect(groups[2] == .snackChoice([day[2], day[3]]))
        #expect(groups[3] == .single(day[4]))
    }

    @Test func aSnackWithNoOptionStaysASingleMeal() {
        let day = [meal("s1", .snack), meal("d", .dinner)]
        #expect(FoundationalWeek.groups(day) == [.single(day[0]), .single(day[1])])
    }

    // MARK: Nominal days

    @Test func nominalDatesReadAsWeekdayNamesOnly() {
        let en = Locale(identifier: "en_US")
        #expect(FoundationalWeek.weekday(for: "2001-01-01", locale: en) == "Monday")
        #expect(FoundationalWeek.weekday(for: "2001-01-07", locale: en) == "Sunday")
        #expect(FoundationalWeek.weekday(for: "2001-01-03", abbreviated: true, locale: en) == "Wed")
        #expect(FoundationalWeek.weekday(for: "2001-01-01", locale: Locale(identifier: "fr_FR"))?.lowercased() == "lundi")
        #expect(FoundationalWeek.weekday(for: "not a date", locale: en) == nil)
    }
}
