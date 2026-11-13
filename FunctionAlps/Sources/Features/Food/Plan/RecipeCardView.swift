import Observation
import SwiftUI

enum RecipeMethodPart: String, CaseIterable, Identifiable, Sendable {
    case preparation, cooking
    var id: String { rawValue }
    var title: String {
        switch self {
        case .preparation: String(localized: "recipe.preparation", defaultValue: "Preparation")
        case .cooking: String(localized: "recipe.cooking", defaultValue: "Cooking")
        }
    }
}

/// One recipe card: the recipe and its lines (RLS: only what the member may read), the stepper, and the approved
/// "Make it…" versions that fit this member.
@MainActor
@Observable
final class RecipeCardModel {
    var state: Loadable<RecipeCard> = .loading
    var servings = 1
    var part: RecipeMethodPart = .preparation
    var versions: [RecipeLogic.VersionOption] = []
    var applyingVersion: String?
    var errorMessage: String?

    private let service: MealPlanService

    init(service: MealPlanService) { self.service = service }

    func load(meal: PlannedMeal, canSwap: Bool, date: String) async {
        state = .loading
        do {
            if let card = try await service.recipe(id: meal.recipe.id) {
                state = .loaded(card)
                servings = RecipeLogic.defaultServings(meal: meal, recipe: card)
                part = RecipeLogic.method(bodyMd: card.bodyMd, steps: card.steps).preparation.isEmpty ? .cooking : .preparation
            } else {
                state = .empty
            }
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown(detail: String(describing: error)))
        }
        // The versions are a bonus: a failed read just hides the row.
        if canSwap, let list = try? await service.candidates(slotId: meal.slotId, date: date, anyMeal: false) {
            versions = RecipeLogic.versions(candidates: list, meal: meal)
        } else {
            versions = []
        }
    }

    func apply(_ option: RecipeLogic.VersionOption, meal: PlannedMeal, date: String) async -> Bool {
        guard applyingVersion == nil else { return false }
        applyingVersion = option.recipeId
        defer { applyingVersion = nil }
        do {
            _ = try await service.swap(slotId: meal.slotId, recipeId: option.recipeId, date: date)
            return true
        } catch let error as AppError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = String(describing: error)
        }
        return false
    }
}

struct RecipeCardView: View {
    @Bindable var plan: MealPlanViewModel
    let open: OpenMeal
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var model: RecipeCardModel?

    var body: some View {
        ZStack {
            if let meal = plan.meal(slotId: open.slotId, date: open.date), let model {
                content(meal, model: model)
            } else {
                FALoadingState()
            }
        }
        .faWall()
        .task {
            if model == nil { model = RecipeCardModel(service: dependencies.mealPlan) }
        }
        .task(id: plan.meal(slotId: open.slotId, date: open.date)?.recipe.id) {
            guard let meal = plan.meal(slotId: open.slotId, date: open.date), let model else { return }
            await model.load(meal: meal, canSwap: planAllowsSwap, date: open.date)
        }
        .sheet(item: Binding(
            get: { plan.swapRequest?.origin == .card ? plan.swapRequest : nil },
            set: { if $0 == nil { plan.swapRequest = nil } }
        )) { request in
            SwapSheet(service: dependencies.mealPlan, request: request) { changed in
                plan.swapRequest = nil
                if changed { Task { await plan.load(refresh: true) } }
            }
            .presentationDetents([.large])
        }
    }

    private var day: PlanDay? { plan.range?.days.first { $0.date == open.date } }
    private var planAllowsSwap: Bool { plan.canSwap(on: day) }
    private var isToday: Bool { open.date == plan.range?.from }
    private var showCalories: Bool { plan.summary(for: day)?.showCalories ?? false }

    @ViewBuilder
    private func content(_ meal: PlannedMeal, model: RecipeCardModel) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    topBar
                    hero(meal)
                    if let note = meal.note { whyCard(note) }
                    recipeBody(meal, model: model)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            actions(meal)
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(String(localized: "action.close", defaultValue: "Close"))
            Spacer()
        }
        .padding(.top, 6)
    }

    private func hero(_ meal: PlannedMeal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(colors: [FAColor.forestMist, FAColor.forestGlow], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "fork.knife").font(.system(size: 38, weight: .light)).foregroundStyle(FAColor.forest.opacity(0.55))
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.lg, style: .continuous))
            .accessibilityHidden(true)
            Text(meal.mealType.localizedName.uppercased() + (isToday ? " · " + String(localized: "plan.recipe.today", defaultValue: "today") : ""))
                .font(FATypography.label).tracking(0.9).foregroundStyle(FAColor.forestSoft)
            Text(meal.recipe.title).font(FATypography.display(26, relativeTo: .title)).foregroundStyle(FAColor.ink)
            HStack(spacing: 14) {
                if let prep = PlanLogic.minutesLabel(meal.recipe.prepMinutes) {
                    Label(String(localized: "recipe.prepMeta", defaultValue: "Prep \(prep)"), systemImage: "clock")
                }
                if let cook = PlanLogic.minutesLabel(meal.recipe.cookMinutes) {
                    Label(String(localized: "recipe.cookMeta", defaultValue: "Cook \(cook)"), systemImage: "flame")
                }
            }
            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            if meal.excluded {
                Text(String(localized: "plan.excluded", defaultValue: "This no longer fits your plan · swap it for another meal"))
                    .font(FATypography.callout).foregroundStyle(FAColor.warning)
            }
        }
    }

    private func whyCard(_ text: String) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 4) {
                TrendLabel(text: String(localized: "recipe.why", defaultValue: "Why this meal"))
                Text(text).font(FATypography.body).foregroundStyle(FAColor.ink)
            }
        }
    }

    @ViewBuilder
    private func recipeBody(_ meal: PlannedMeal, model: RecipeCardModel) -> some View {
        switch model.state {
        case .loading:
            FALoadingState().frame(height: 160)
        case .failed(let error):
            FAErrorState(title: String(localized: "recipe.error", defaultValue: "Couldn't load this recipe"), message: error.userMessage) {
                Task { await model.load(meal: meal, canSwap: planAllowsSwap, date: open.date) }
            }
            .frame(height: 240)
        case .empty:
            FAEmptyState(title: String(localized: "recipe.unavailable.title", defaultValue: "Recipe not available"),
                         message: String(localized: "recipe.unavailable.message", defaultValue: "This recipe can't be shown right now. Your practitioner can tell you how to make it."),
                         systemImage: "book.closed")
        case .loaded(let card):
            makeIt(meal, model: model)
            ingredients(card, model: model)
            method(card, model: model)
            nutrition(card)
        }
    }

    // MARK: Make it…

    @ViewBuilder
    private func makeIt(_ meal: PlannedMeal, model: RecipeCardModel) -> some View {
        if planAllowsSwap, !model.versions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TrendLabel(text: String(localized: "recipe.makeIt", defaultValue: "Make it…"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.versions) { option in
                            Button {
                                Task { if await model.apply(option, meal: meal, date: open.date) { await plan.load(refresh: true) } }
                            } label: {
                                HStack(spacing: 6) {
                                    if model.applyingVersion == option.recipeId { ProgressView().controlSize(.mini) }
                                    Text(option.label)
                                }
                                .font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                                .foregroundStyle(FAColor.ink)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background(Color.white.opacity(0.6), in: Capsule())
                                .overlay { Capsule().strokeBorder(FAColor.forestSoft.opacity(0.45), lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            .disabled(model.applyingVersion != nil)
                        }
                    }
                }
                Text(String(localized: "recipe.makeIt.note", defaultValue: "Approved versions only. Your practitioner will see the change, and your grocery list updates."))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                if let message = model.errorMessage {
                    Text(message).font(FATypography.caption).foregroundStyle(FAColor.danger)
                }
            }
        }
    }

    // MARK: Ingredients

    private func ingredients(_ card: RecipeCard, model: RecipeCardModel) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TrendLabel(text: String(localized: "recipe.ingredients", defaultValue: "Ingredients"))
                    Spacer()
                    stepper(model)
                }
                ForEach(card.ingredients) { line in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(RecipeLogic.ingredientName(line)).font(FATypography.body).foregroundStyle(FAColor.ink)
                            if let note = line.prepNote {
                                Text(note).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            } else if line.isOptional {
                                Text(String(localized: "recipe.optional", defaultValue: "optional")).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            }
                        }
                        Spacer(minLength: 12)
                        Text(RecipeLogic.quantityLabel(line, recipeServings: card.servings, chosen: model.servings))
                            .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
                if card.ingredients.isEmpty {
                    Text(String(localized: "recipe.noIngredients", defaultValue: "No ingredient list for this recipe.")).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
    }

    private func stepper(_ model: RecipeCardModel) -> some View {
        HStack(spacing: 4) {
            Button { model.servings = max(RecipeLogic.servingsRange.lowerBound, model.servings - 1) } label: {
                Image(systemName: "minus.circle").font(.system(size: 20)).frame(width: 44, height: 44)
            }
            .disabled(model.servings <= RecipeLogic.servingsRange.lowerBound)
            .accessibilityLabel(String(localized: "recipe.servings.less", defaultValue: "Fewer servings"))
            Text(String(localized: "recipe.servings", defaultValue: "\(model.servings) servings"))
                .font(FATypography.sans(13, .semibold, relativeTo: .footnote)).monospacedDigit()
            Button { model.servings = min(RecipeLogic.servingsRange.upperBound, model.servings + 1) } label: {
                Image(systemName: "plus.circle").font(.system(size: 20)).frame(width: 44, height: 44)
            }
            .disabled(model.servings >= RecipeLogic.servingsRange.upperBound)
            .accessibilityLabel(String(localized: "recipe.servings.more", defaultValue: "More servings"))
        }
        .foregroundStyle(FAColor.brand)
    }

    // MARK: Method

    @ViewBuilder
    private func method(_ card: RecipeCard, model: RecipeCardModel) -> some View {
        let m = RecipeLogic.method(bodyMd: card.bodyMd, steps: card.steps)
        if !m.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 12) {
                    if m.isSplit {
                        FASegmentedControl(options: RecipeMethodPart.allCases, selection: model.part, title: \.title) { model.part = $0 }
                    } else {
                        TrendLabel(text: String(localized: "recipe.method", defaultValue: "Method"))
                    }
                    let steps = m.isSplit ? (model.part == .preparation ? m.preparation : m.cooking) : (m.preparation + m.cooking)
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)").font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.forestSoft)
                                .frame(width: 20, alignment: .trailing)
                            Text(step).font(FATypography.body).foregroundStyle(FAColor.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: Nutrition

    @ViewBuilder
    private func nutrition(_ card: RecipeCard) -> some View {
        if let n = card.nutrition {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    TrendLabel(text: String(localized: "recipe.nutrition", defaultValue: "Per serving"))
                    HStack(spacing: 18) {
                        if showCalories, let kcal = n.kcal { stat(String(Int(kcal.rounded())), String(localized: "recipe.kcal", defaultValue: "kcal")) }
                        if let v = n.proteinG { stat(grams(v), String(localized: "recipe.protein", defaultValue: "protein")) }
                        if let v = n.carbsG { stat(grams(v), String(localized: "recipe.carbs", defaultValue: "carbs")) }
                        if let v = n.fatG { stat(grams(v), String(localized: "recipe.fat", defaultValue: "fat")) }
                        if let v = n.fiberG { stat(grams(v), String(localized: "recipe.fiber", defaultValue: "fibre")) }
                    }
                    if n.total > 0 {
                        Text(String(localized: "recipe.coverage", defaultValue: "Measured for \(n.measured) of \(n.total) nutrients; \(n.wellCovered) are fully covered by the ingredients' data. A nutrient with no data is left out, never counted as zero."))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
            }
        }
    }

    private func grams(_ value: Double) -> String { GroceryLogic.number(value, maxFraction: 0) + " g" }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(FATypography.sans(16, .bold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
            Text(label).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ meal: PlannedMeal) -> some View {
        HStack(spacing: 10) {
            if meal.isLogged {
                Label(String(localized: "plan.eaten", defaultValue: "Logged from your plan"), systemImage: "checkmark.circle.fill")
                    .font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.forestSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isToday && !meal.excluded {
                FAButton(title: String(localized: "plan.ateThis", defaultValue: "I ate this"), isLoading: plan.isBusy(meal.slotId)) {
                    plan.ateThis(meal, on: open.date)
                    dismiss()
                }
            }
            if planAllowsSwap && !meal.isLogged {
                FAButton(title: String(localized: "plan.swap", defaultValue: "Swap"), style: .secondary) {
                    plan.askSwap(meal, on: open.date, from: .card)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.clear)
    }
}
