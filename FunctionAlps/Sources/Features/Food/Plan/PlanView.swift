import SwiftUI

/// Food › Plan: the day strip and the day's planned meals. Each row can be eaten ("I ate this"), swapped, or opened.
struct PlanView: View {
    @Bindable var plan: MealPlanViewModel

    var body: some View {
        switch plan.plan {
        case .loading:
            FALoadingState().frame(height: 240)
        case .failed(let error):
            FAErrorState(title: String(localized: "plan.error.title", defaultValue: "Couldn't load your plan"), message: error.userMessage) {
                Task { await plan.load() }
            }
            .frame(height: 280)
        case .empty:
            FAEmptyState(
                title: String(localized: "plan.empty.title", defaultValue: "No meal plan yet"),
                message: String(localized: "plan.empty.message", defaultValue: "When your practitioner shares a meal plan, it appears here with its recipes and your grocery list."),
                systemImage: "fork.knife"
            )
            .padding(.vertical, 40)
        case .loaded(let range):
            content(range)
        }
    }

    private func content(_ range: MealPlanRange) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DayStrip(days: range.days, today: range.from, selected: plan.selectedDate) { plan.selectedDate = $0 }
            if let day = plan.selectedDay {
                dayHeading(day, range: range)
                LazyVStack(spacing: 10) {
                    ForEach(day.meals) { meal in
                        PlannedMealRow(
                            meal: meal,
                            canSwap: plan.canSwap(on: day),
                            canEat: day.date == range.from,
                            busy: plan.isBusy(meal.slotId),
                            onOpen: { plan.openMeal = OpenMeal(slotId: meal.slotId, date: day.date) },
                            onEat: { plan.ateThis(meal, on: day.date) },
                            onUndo: { plan.undoLogged(meal) },
                            onSwap: { plan.askSwap(meal, on: day.date, from: .list) }
                        )
                    }
                }
                if day.meals.isEmpty {
                    Text(String(localized: "plan.day.empty", defaultValue: "Nothing planned for this day."))
                        .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
    }

    private func dayHeading(_ day: PlanDay, range: MealPlanRange) -> some View {
        let isToday = day.date == range.from
        let heading = PlanLogic.dayHeading(for: day.date)
        return Text(isToday ? String(localized: "plan.day.today", defaultValue: "Today · \(heading)") : heading)
            .font(FATypography.headline)
            .foregroundStyle(FAColor.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One chip per day of the range.
private struct DayStrip: View {
    let days: [PlanDay]
    let today: String
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days) { day in
                    let on = day.date == selected
                    let label = PlanLogic.stripLabel(for: day.date)
                    Button { onSelect(day.date) } label: {
                        VStack(spacing: 2) {
                            Text(label.weekday.uppercased()).font(FATypography.label).tracking(0.6)
                            Text(label.number).font(FATypography.sans(17, .bold, relativeTo: .headline))
                            Circle().fill(day.date == today ? FAColor.forestSoft : .clear).frame(width: 5, height: 5)
                        }
                        .foregroundStyle(on ? Color.white : FAColor.ink)
                        .frame(width: 48, height: 64)
                        .background(on ? FAColor.forest : Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(PlanLogic.dayHeading(for: day.date))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// One planned meal: its type, title, meta, and the two actions.
struct PlannedMealRow: View {
    let meal: PlannedMeal
    let canSwap: Bool
    /// "I ate this" is for today; other days are for planning ahead.
    let canEat: Bool
    let busy: Bool
    let onOpen: () -> Void
    let onEat: () -> Void
    let onUndo: () -> Void
    let onSwap: () -> Void

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(slotLabel.uppercased()).font(FATypography.label).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
                        Text(meal.recipe.title).font(FATypography.sans(16, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                            .multilineTextAlignment(.leading)
                        if let meta { Text(meta).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary) }
                        if meal.swapped, let was = meal.prescribedTitle {
                            Text(String(localized: "plan.swapped", defaultValue: "Swapped · instead of \(was)"))
                                .font(FATypography.caption).foregroundStyle(FAColor.forestSoft)
                        }
                        if meal.excluded {
                            Text(String(localized: "plan.excluded", defaultValue: "This no longer fits your plan · swap it for another meal"))
                                .font(FATypography.caption).foregroundStyle(FAColor.warning)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "plan.openRecipe.hint", defaultValue: "Opens the recipe"))
                actions
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if meal.isLogged {
            HStack {
                Label(String(localized: "plan.eaten", defaultValue: "Logged from your plan"), systemImage: "checkmark.circle.fill")
                    .font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft)
                Spacer()
                Button(action: onUndo) {
                    Text(String(localized: "food.relog.undo", defaultValue: "Undo"))
                        .font(FATypography.sans(12.5, .bold, relativeTo: .caption)).foregroundStyle(FAColor.brand)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(busy)
            }
        } else {
            HStack(spacing: 10) {
                if canEat && !meal.excluded {
                    FAButton(title: String(localized: "plan.ateThis", defaultValue: "I ate this"), isLoading: busy, action: onEat)
                }
                if canSwap {
                    FAButton(title: String(localized: "plan.swap", defaultValue: "Swap"), style: .secondary, isEnabled: !busy, action: onSwap)
                }
            }
        }
    }

    private var slotLabel: String {
        if let moment = meal.moment?.nilIfEmpty, PlanLogic.mealType(moment) == .other { return moment }
        return meal.mealType.localizedName
    }

    private var meta: String? {
        let parts = [PlanLogic.minutesLabel(meal.recipe.totalMinutes), PlanLogic.portionsLabel(meal.portions), kcalLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var kcalLabel: String? {
        guard let kcal = meal.recipe.kcalPerServing else { return nil }
        return String(localized: "plan.kcal", defaultValue: "\(Int(kcal.rounded())) kcal")
    }
}

/// "From your plan" inside the capture card: today's next planned meal, one tap to log it.
struct FromYourPlanStrip: View {
    let meal: PlannedMeal
    let canSwap: Bool
    let busy: Bool
    let onOpen: () -> Void
    let onEat: () -> Void
    let onSwap: () -> Void
    let onSomethingElse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "plan.strip.caption", defaultValue: "From your plan · \(meal.mealType.localizedName.lowercased())").uppercased())
                        .font(FATypography.label).tracking(0.9).foregroundStyle(FAColor.forestSoft)
                    Text(meal.recipe.title).font(FATypography.sans(16, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading)
                    if let minutes = PlanLogic.minutesLabel(meal.recipe.totalMinutes) {
                        Text(minutes).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                FAButton(title: String(localized: "plan.ateThis", defaultValue: "I ate this"), isLoading: busy, action: onEat)
                if canSwap {
                    FAButton(title: String(localized: "plan.swap", defaultValue: "Swap"), style: .secondary, isEnabled: !busy, action: onSwap)
                }
            }
            Button(action: onSomethingElse) {
                Text(String(localized: "plan.strip.somethingElse", defaultValue: "I ate something else"))
                    .font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.brand)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(FAColor.separator).frame(height: 1) }
        .padding(.bottom, 12)
    }
}
