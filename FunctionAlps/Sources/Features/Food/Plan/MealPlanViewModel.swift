import Foundation
import Observation

/// Logging · Plan · Groceries: the switch at the top of the Food tab.
enum FoodSection: String, CaseIterable, Identifiable, Sendable {
    case logging, plan, groceries
    var id: String { rawValue }

    var title: String {
        switch self {
        case .logging: String(localized: "food.section.logging", defaultValue: "Logging")
        case .plan: String(localized: "food.section.plan", defaultValue: "Plan")
        case .groceries: String(localized: "food.section.groceries", defaultValue: "Groceries")
        }
    }
}

/// A swap sheet to show, and from which surface it was opened (the list and the recipe card each present their own).
struct SwapRequest: Identifiable, Equatable {
    enum Origin: String { case list, card }
    let meal: PlannedMeal
    let date: String
    let origin: Origin
    var id: String { "\(origin.rawValue)-\(meal.slotId)-\(date)" }
}

/// The recipe card to show: a planned meal on a day. Looked up live, so a swap or a log refreshes the card.
struct OpenMeal: Identifiable, Equatable {
    let slotId: String
    let date: String
    var id: String { "\(slotId)-\(date)" }
}

/// The Plan and Groceries views and the "From your plan" strip share this one read of the plan.
@MainActor
@Observable
final class MealPlanViewModel {
    var plan: Loadable<MealPlanRange> = .loading
    var selectedDate: String?
    var groceries: Loadable<GroceryList> = .loading
    var errorMessage: String?
    var swapRequest: SwapRequest?
    var openMeal: OpenMeal?
    var showShareSheet = false
    private(set) var busySlots: Set<String> = []

    /// A meal log was written (id, recipe title, kcal when the plan shows calories): the Food screen shows its toast.
    @ObservationIgnored var onLogged: (@MainActor (String, String, Double?) -> Void)?
    /// The member's meal logs changed under the plan (an undo): the Food screen reloads them.
    @ObservationIgnored var onMealsChanged: (@MainActor () -> Void)?

    private let service: MealPlanService
    private let meals: MealService
    private let members: MemberService
    private let auth: AuthService

    init(service: MealPlanService, meals: MealService, members: MemberService, auth: AuthService) {
        self.service = service
        self.meals = meals
        self.members = members
        self.auth = auth
    }

    // MARK: Derived

    var range: MealPlanRange? { plan.value }

    var selectedDay: PlanDay? {
        guard let range else { return nil }
        return range.days.first { $0.date == selectedDate }
    }

    var todayDay: PlanDay? { range.flatMap { PlanLogic.todayDay(in: $0) } }

    /// "From your plan": today's next uneaten meal that still fits the member.
    var nextMeal: (meal: PlannedMeal, date: String)? {
        guard let day = todayDay, let meal = PlanLogic.nextMeal(in: day) else { return nil }
        return (meal, day.date)
    }

    func summary(for day: PlanDay?) -> PlanSummary? {
        guard let range, let day else { return nil }
        return range.plan(for: day)
    }

    func meal(slotId: String, date: String) -> PlannedMeal? {
        range?.days.first { $0.date == date }?.meals.first { $0.slotId == slotId }
    }

    func canSwap(on day: PlanDay?) -> Bool { summary(for: day)?.allowSwaps ?? false }

    func isBusy(_ slotId: String) -> Bool { busySlots.contains(slotId) }

    // MARK: Plan

    func load(refresh: Bool = false) async {
        if !refresh, plan.value == nil { plan = .loading }
        do {
            let range = try await service.plan()
            if range.isEmpty {
                plan = .empty
                selectedDate = nil
            } else {
                plan = .loaded(range)
                selectedDate = PlanLogic.selectedDate(days: range.days, today: range.from, preferred: selectedDate)
            }
        } catch {
            await handle(error, context: "plan.load", keepScreen: plan.value != nil)
        }
    }

    /// "I ate this": the server writes the meal log; the toast offers Undo (which deletes it through the existing path).
    func ateThis(_ meal: PlannedMeal, on date: String) {
        guard !busySlots.contains(meal.slotId), !meal.isLogged else { return }
        busySlots.insert(meal.slotId)
        let showCalories = summary(for: range?.days.first { $0.date == date })?.showCalories ?? false
        Task {
            defer { busySlots.remove(meal.slotId) }
            do {
                let result = try await service.logPlanned(slotId: meal.slotId, date: date)
                if result.created {
                    let kcal = showCalories ? meal.recipe.kcalPerServing.map { $0 * (meal.portions ?? 1) } : nil
                    onLogged?(result.mealLogId, meal.recipe.title, kcal)
                }
                await load(refresh: true)
            } catch {
                await handle(error, context: "plan.ateThis", keepScreen: true)
            }
        }
    }

    /// Takes a logged planned meal back: the log is deleted through the same path as the toast's Undo.
    func undoLogged(_ meal: PlannedMeal) {
        guard let id = meal.loggedMealId, !busySlots.contains(meal.slotId) else { return }
        busySlots.insert(meal.slotId)
        Task {
            defer { busySlots.remove(meal.slotId) }
            await meals.deleteRelogged(id: id)
            await load(refresh: true)
            onMealsChanged?()
        }
    }

    func askSwap(_ meal: PlannedMeal, on date: String, from origin: SwapRequest.Origin) {
        swapRequest = SwapRequest(meal: meal, date: date, origin: origin)
    }

    // MARK: Groceries

    func loadGroceries(refresh: Bool = false) async {
        if !refresh, groceries.value == nil { groceries = .loading }
        do {
            let list = try await service.groceries()
            groceries = list.isEmpty ? .empty : .loaded(list)
        } catch {
            await handle(error, context: "groceries.load", keepScreen: groceries.value != nil, grocery: true)
        }
    }

    /// Ticks a line at once and saves it; a failed save puts the tick back and says so.
    func toggle(_ target: GroceryTarget, checked: Bool) {
        guard let before = groceries.value else { return }
        groceries = .loaded(GroceryLogic.setting(target, checked: checked, in: before))
        Task {
            do {
                let member = try await members.currentMember()
                try await service.setChecked(patientId: member.patientId, list: before, target: target, checked: checked)
            } catch {
                groceries = .loaded(before)
                await handle(error, context: "groceries.tick", keepScreen: true)
            }
        }
    }

    // MARK: Errors

    private func handle(_ error: any Error, context: StaticString, keepScreen: Bool, grocery: Bool = false) async {
        if let app = error as? AppError {
            Log.error(app, in: Log.data, context: context)
            if case .unauthorized = app { await auth.handleUnauthorized(); return }
            if keepScreen { errorMessage = app.userMessage } else if grocery { groceries = .failed(app) } else { plan = .failed(app) }
        } else {
            Log.data.error("\(context, privacy: .public): \(String(describing: error), privacy: .public)")
            let app = AppError.unknown(detail: String(describing: error))
            if keepScreen { errorMessage = app.userMessage } else if grocery { groceries = .failed(app) } else { plan = .failed(app) }
        }
    }
}
