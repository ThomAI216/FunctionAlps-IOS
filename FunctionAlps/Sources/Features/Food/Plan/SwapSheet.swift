import Observation
import SwiftUI

/// The swap candidates for one planned meal on one day. The server lists only recipes that fit this member
/// (their allergies and avoid list are a hard filter), same meal type first; "Any meal" widens it.
@MainActor
@Observable
final class SwapListModel {
    var state: Loadable<[SwapCandidate]> = .loading
    var anyMeal = false
    var applyingId: String?
    var errorMessage: String?

    private let service: MealPlanService
    let meal: PlannedMeal
    let date: String

    init(service: MealPlanService, meal: PlannedMeal, date: String) {
        self.service = service
        self.meal = meal
        self.date = date
    }

    func load() async {
        state = .loading
        do {
            let list = try await service.candidates(slotId: meal.slotId, date: date, anyMeal: anyMeal)
            state = list.isEmpty ? .empty : .loaded(list.filter { !$0.isCurrent })
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown(detail: String(describing: error)))
        }
    }

    func setAnyMeal(_ on: Bool) {
        anyMeal = on
        Task { await load() }
    }

    /// Applies the swap; true when the plan changed.
    func apply(_ candidate: SwapCandidate) async -> Bool {
        guard applyingId == nil else { return false }
        applyingId = candidate.recipeId
        defer { applyingId = nil }
        do {
            _ = try await service.swap(slotId: meal.slotId, recipeId: candidate.recipeId, date: date)
            return true
        } catch let error as AppError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = String(describing: error)
        }
        return false
    }
}

struct SwapSheet: View {
    @State private var model: SwapListModel
    let onDone: (Bool) -> Void

    init(service: MealPlanService, request: SwapRequest, onDone: @escaping (Bool) -> Void) {
        _model = State(initialValue: SwapListModel(service: service, meal: request.meal, date: request.date))
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "swap.title", defaultValue: "Swap \(model.meal.mealType.localizedName.lowercased())"))
                    .font(FATypography.title).foregroundStyle(FAColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(String(localized: "action.cancel", defaultValue: "Cancel")) { onDone(false) }
                    .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.brand)
                    .frame(minHeight: 44)
            }
            Text(String(localized: "swap.intro", defaultValue: "All of these fit your plan. Your practitioner will see the swap, and your grocery list updates."))
                .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
            Toggle(String(localized: "swap.anyMeal", defaultValue: "Any meal"), isOn: Binding(get: { model.anyMeal }, set: { model.setAnyMeal($0) }))
                .font(FATypography.sans(14, .medium, relativeTo: .subheadline))
                .tint(FAColor.forestSoft)
            if let message = model.errorMessage {
                Text(message).font(FATypography.caption).foregroundStyle(FAColor.danger)
            }
            list
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .faWall()
        .task { await model.load() }
    }

    @ViewBuilder
    private var list: some View {
        switch model.state {
        case .loading:
            FALoadingState()
        case .failed(let error):
            FAErrorState(title: String(localized: "swap.error", defaultValue: "Couldn't load the options"), message: error.userMessage) {
                Task { await model.load() }
            }
        case .empty:
            FAEmptyState(title: String(localized: "swap.empty.title", defaultValue: "No other options"),
                         message: String(localized: "swap.empty.message", defaultValue: "Nothing else in the recipe library fits this meal right now."),
                         systemImage: "arrow.2.squarepath")
        case .loaded(let candidates):
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(candidates) { candidate in
                        FACard {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.title).font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                                    if let meta = meta(candidate) {
                                        Text(meta).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                FAButton(title: String(localized: "swap.use", defaultValue: "Use"), isLoading: model.applyingId == candidate.recipeId,
                                         isEnabled: model.applyingId == nil) {
                                    Task { if await model.apply(candidate) { onDone(true) } }
                                }
                                .frame(width: 84)
                            }
                        }
                    }
                }
            }
        }
    }

    private func meta(_ c: SwapCandidate) -> String? {
        var parts: [String] = []
        switch c.source {
        case .alternative: parts.append(String(localized: "swap.source.alternative", defaultValue: "Suggested by your practitioner"))
        case .variant: if let v = RecipeLogic.versionLabel(c.variantKind) { parts.append(v) }
        case .mine: parts.append(String(localized: "swap.source.mine", defaultValue: "Your recipe"))
        case .prescribed, .library: break
        }
        if let minutes = PlanLogic.minutesLabel(c.totalMinutes) { parts.append(minutes) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
