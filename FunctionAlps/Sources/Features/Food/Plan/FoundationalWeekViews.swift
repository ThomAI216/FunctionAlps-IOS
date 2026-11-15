import SwiftUI

/// A recipe photo from its https URL: a placeholder while it loads, the same placeholder when it fails (the screen never
/// depends on a photo). Not every URL is trusted: `FoundationalWeek.imageURL` accepts https only.
struct RecipePhoto: View {
    let urlString: String?
    /// The recipe's title when the photo stands alone (the card's header); nil when the title sits right beside it, so VoiceOver skips it.
    var accessibilityTitle: String?

    var body: some View {
        // The clear base takes the size the caller gives; the photo fills it and is cropped, never pushing the layout wider.
        Color.clear.overlay { content }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle ?? "")
        .accessibilityHidden(accessibilityTitle == nil)
    }

    private var content: some View {
        Group {
            if let url = FoundationalWeek.imageURL(urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .empty: placeholder(loading: true)
                    default: placeholder(loading: false)
                    }
                }
            } else {
                placeholder(loading: false)
            }
        }
    }

    private func placeholder(loading: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [FAColor.forestMist, FAColor.forestGlow], startPoint: .topLeading, endPoint: .bottomTrailing)
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "fork.knife").font(.system(size: 20, weight: .light)).foregroundStyle(FAColor.forest.opacity(0.55))
            }
        }
    }
}

/// Which banner sits above the example week.
enum FoundationalBanner {
    /// The member has no delivered plan yet.
    case noPlan
    /// The member has a plan: this is a reference week beside it.
    case reference

    var text: String {
        switch self {
        case .noPlan:
            String(localized: "foundational.banner.noPlan", defaultValue: "Foundational week: an example of how your meal plan will look. Your practitioner will build your own.")
        case .reference:
            String(localized: "foundational.banner.reference", defaultValue: "Foundational week: a reference week from FunctionAlps. Your own plan is under Plan.")
        }
    }

    /// Why "I ate this", swaps and "Make it…" are switched off.
    var disabledReason: String {
        switch self {
        case .noPlan:
            String(localized: "foundational.disabled.noPlan", defaultValue: "Available once your own plan is ready")
        case .reference:
            String(localized: "foundational.disabled.reference", defaultValue: "Available on your own plan, not on the reference week")
        }
    }
}

struct FoundationalBannerView: View {
    let banner: FoundationalBanner

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "leaf").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.forestSoft).accessibilityHidden(true)
            Text(banner.text).font(FATypography.callout).foregroundStyle(FAColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(FAColor.forestMist.opacity(0.6), in: RoundedRectangle(cornerRadius: FACornerRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The "Foundational week" entry every member with a plan finds under Plan and Groceries.
struct FoundationalWeekEntry: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            FACard {
                HStack(spacing: 12) {
                    Image(systemName: "leaf").font(.system(size: 18, weight: .semibold)).foregroundStyle(FAColor.brand).frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "foundational.entry.title", defaultValue: "Foundational week"))
                            .font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                        Text(String(localized: "foundational.entry.detail", defaultValue: "A reference week of meals and groceries from FunctionAlps."))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
        .accessibilityHint(String(localized: "foundational.entry.hint", defaultValue: "Opens the reference week"))
    }
}

/// One meal of the example week: photo, what it is, its title and time. Tapping opens the recipe.
struct ExampleMealButton: View {
    let meal: PlannedMeal
    /// What to call this meal above its title: the option for a snack choice, else the meal type.
    let label: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                RecipePhoto(urlString: meal.recipe.imagePath)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(label.uppercased()).font(FATypography.label).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
                    Text(meal.recipe.title).font(FATypography.sans(16, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading)
                    if let minutes = PlanLogic.minutesLabel(meal.recipe.totalMinutes) {
                        Text(minutes).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "plan.openRecipe.hint", defaultValue: "Opens the recipe"))
    }
}

/// A day of the example week: single meals as cards; the two snacks as one "one or the other" group.
struct ExampleDayMeals: View {
    let day: PlanDay
    let banner: FoundationalBanner
    let onOpen: (PlannedMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(FoundationalWeek.groups(day.meals).enumerated()), id: \.offset) { _, group in
                switch group {
                case .single(let meal):
                    FACard { ExampleMealButton(meal: meal, label: label(meal)) { onOpen(meal) } }
                case .snackChoice(let options):
                    FACard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "foundational.snack.choice", defaultValue: "Snack: one or the other"))
                                .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(options) { meal in
                                ExampleMealButton(meal: meal, label: meal.optionLabel ?? label(meal)) { onOpen(meal) }
                            }
                        }
                    }
                }
            }
            Label(banner.disabledReason, systemImage: "lock")
                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
        }
    }

    private func label(_ meal: PlannedMeal) -> String {
        if let moment = meal.moment?.nonBlank, PlanLogic.mealType(moment) == .other { return moment }
        return meal.mealType.localizedName
    }
}

private enum FoundationalTab: String, CaseIterable, Identifiable {
    case week, groceries
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: String(localized: "foundational.tab.week", defaultValue: "Week")
        case .groceries: String(localized: "foundational.tab.groceries", defaultValue: "Groceries")
        }
    }
}

/// The reference week for a member who has a plan: Week and Groceries, read only.
struct FoundationalWeekSheet: View {
    @Bindable var example: MealPlanViewModel
    let onDone: () -> Void
    @State private var tab: FoundationalTab = .week

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(localized: "foundational.entry.title", defaultValue: "Foundational week")).font(FATypography.title).foregroundStyle(FAColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(String(localized: "action.done", defaultValue: "Done"), action: onDone)
                        .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.brand).frame(minHeight: 44)
                }
                FoundationalBannerView(banner: .reference)
                FASegmentedControl(options: FoundationalTab.allCases, selection: tab, title: \.title) { tab = $0 }
                switch tab {
                case .week: PlanView(plan: example, banner: .reference)
                case .groceries: GroceriesView(plan: example)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .faWall()
        .sheet(item: $example.openMeal) { open in
            RecipeCardView(plan: example, open: open, banner: .reference)
        }
    }
}
