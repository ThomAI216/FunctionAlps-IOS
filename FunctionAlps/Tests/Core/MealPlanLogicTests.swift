import Foundation
import Testing
@testable import FunctionAlps

private func meal(_ id: String, type: MealLog.MealType = .dinner, logged: String? = nil, excluded: Bool = false) -> PlannedMeal {
    PlannedMeal(
        slotId: id, momentUid: nil, moment: nil, mealType: type, note: nil, portions: 1, servings: 2, swapped: false, swapKind: nil,
        recipe: PlannedRecipe(id: "r-\(id)", title: "Recipe \(id)", slug: nil, imagePath: nil, prepMinutes: 10, cookMinutes: 15,
                              servings: 2, variantKind: nil, own: false, kcalPerServing: nil),
        prescribedId: nil, prescribedTitle: nil, excluded: excluded, alternativeIds: [], loggedMealId: logged
    )
}

private func day(_ date: String, _ meals: [PlannedMeal] = []) -> PlanDay { PlanDay(date: date, planId: "p1", meals: meals) }

@Suite("Meal plan logic")
struct MealPlanLogicTests {
    @Test func slotMappingFoldsMomentsIntoMealTypes() {
        #expect(PlanLogic.mealType("breakfast") == .breakfast)
        #expect(PlanLogic.mealType("Lunch") == .lunch)
        #expect(PlanLogic.mealType("mid-morning snack") == .snack)
        #expect(PlanLogic.mealType("afternoon_snack") == .snack)
        #expect(PlanLogic.mealType("supper") == .dinner)
        #expect(PlanLogic.mealType("pre-workout") == .other)
        #expect(PlanLogic.mealType(nil) == .other)
        #expect(PlanLogic.mealType("  ") == .other)
    }

    @Test func selectedDatePrefersThePickedDayThenTodayThenTheNextOne() {
        let days = [day("2026-11-16"), day("2026-11-17"), day("2026-11-18")]
        #expect(PlanLogic.selectedDate(days: days, today: "2026-11-16", preferred: "2026-11-18") == "2026-11-18")
        #expect(PlanLogic.selectedDate(days: days, today: "2026-11-17", preferred: "2026-12-01") == "2026-11-17")
        #expect(PlanLogic.selectedDate(days: days, today: "2026-11-15", preferred: nil) == "2026-11-16")
        #expect(PlanLogic.selectedDate(days: days, today: "2026-12-30", preferred: nil) == "2026-11-16")
        #expect(PlanLogic.selectedDate(days: [], today: "2026-11-16", preferred: nil) == nil)
    }

    @Test func nextMealSkipsEatenAndExcludedMeals() {
        let d = day("2026-11-16", [meal("a", type: .breakfast, logged: "log1"), meal("b", type: .lunch, excluded: true), meal("c")])
        #expect(PlanLogic.nextMeal(in: d)?.slotId == "c")
        let done = day("2026-11-16", [meal("a", logged: "x")])
        #expect(PlanLogic.nextMeal(in: done) == nil)
        #expect(PlanLogic.nextMeal(in: nil) == nil)
    }

    @Test func todayIsTheRangeStart() {
        let range = MealPlanRange(from: "2026-11-17", to: "2026-11-23", plans: [], days: [day("2026-11-16"), day("2026-11-17", [meal("a")])])
        #expect(PlanLogic.todayDay(in: range)?.meals.count == 1)
    }

    @Test func dayKeysRoundTripInTheCalendarsZone() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
        let date = try #require(PlanLogic.date(from: "2026-11-16", calendar: cal))
        #expect(PlanLogic.dayKey(date, calendar: cal) == "2026-11-16")
        #expect(PlanLogic.date(from: "nonsense", calendar: cal) == nil)
    }

    @Test func stripLabelsAreShort() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
        let label = PlanLogic.stripLabel(for: "2026-11-17", calendar: cal, locale: Locale(identifier: "en_US"))
        #expect(label.number == "17")
        #expect(label.weekday == "Tue")
        #expect(PlanLogic.dayHeading(for: "2026-11-17", calendar: cal, locale: Locale(identifier: "en_US")) == "Tue, Nov 17")
    }

    @Test func rangeFindsTheSummaryOfADaysPlan() {
        let p = PlanSummary(id: "p1", title: "Week", startDate: "2026-11-16", endDate: "2026-11-22", people: 2, showCalories: false, allowSwaps: false)
        let range = MealPlanRange(from: "2026-11-16", to: "2026-11-22", plans: [p], days: [day("2026-11-16")])
        #expect(range.plan(for: range.days[0])?.allowSwaps == false)
    }
}
