import PhotosUI
import SwiftUI

struct FoodView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: FoodViewModel?

    var body: some View {
        ZStack {
            if let model {
                FoodScreen(model: model)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = FoodViewModel(members: dependencies.members, meals: dependencies.meals, auth: dependencies.auth)
                model = m
                await m.load()
            }
        }
    }
}

private struct FoodScreen: View {
    @Bindable var model: FoodViewModel
    @State private var capture = MealCaptureCoordinator()
    @FocusState private var describeFocused: Bool

    var body: some View {
        content
            .mealCaptureHost(capture) { model.captureFinished() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            FALoadingState()
        case .failed(let error):
            FAErrorState(title: String(localized: "food.error.title", defaultValue: "Couldn't load your meals"), message: error.userMessage) {
                Task { await model.load() }
            }
        case .empty:
            FAErrorState(
                title: String(localized: "home.notRegistered.title", defaultValue: "Almost there"),
                message: String(localized: "home.notRegistered.message", defaultValue: "This account isn't linked to a FunctionAlps client profile yet. Finish onboarding on the FunctionAlps web app, then come back."),
                retryTitle: String(localized: "action.retry", defaultValue: "Try again")
            ) { Task { await model.load() } }
        case .loaded(let content):
            ScrollView {
                VStack(alignment: .leading, spacing: FASpacing.lg) {
                    header
                    photoHero
                    describeCard
                    MacrosTodayCard(meals: model.todayMeals(content), profile: content.member.profile)
                    history(content)
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.load(refresh: true) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FASpacing.xs) {
            Text(String(localized: "food.kicker", defaultValue: "Nutrition").uppercased())
                .font(FATypography.label)
                .foregroundStyle(FAColor.accent)
                .tracking(0.8)
            Text(String(localized: "food.title", defaultValue: "What did you eat?"))
                .font(FATypography.largeTitle)
                .foregroundStyle(FAColor.ink)
        }
        .padding(.top, FASpacing.md)
        .accessibilityElement(children: .combine)
    }

    /// The Food tab's hero: the one-tap way in. Tapping opens the phone's own chooser.
    private var photoHero: some View {
        Button { capture.openPhotoChooser() } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [FAColor.forestSoft, FAColor.forest, FAColor.forestDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 220, height: 220)
                    .offset(x: 200, y: -90)
                VStack(alignment: .leading, spacing: FASpacing.sm) {
                    HStack(spacing: FASpacing.sm) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text(String(localized: "food.photo.cta", defaultValue: "Photo"))
                            .font(FATypography.headline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.18), in: Capsule())
                    Text(String(localized: "food.photo.headline", defaultValue: "Snap your plate. We read it for you."))
                        .font(FATypography.title)
                    Text(String(localized: "food.photo.sub", defaultValue: "Foods, portions, calories, macros and how the meal is likely to sit."))
                        .font(FATypography.caption)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(FASpacing.md)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
            .shadow(color: FAColor.forest.opacity(0.25), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "food.photo.title", defaultValue: "Add your meal by photo"))
    }

    private var describeCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.sm) {
                Text(String(localized: "food.describe.title", defaultValue: "Or describe it"))
                    .font(FATypography.headline)
                    .foregroundStyle(FAColor.ink)
                TextField(
                    String(localized: "food.describe.placeholder", defaultValue: "e.g. grilled chicken, sweet potato, salad"),
                    text: $model.description,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .font(FATypography.body)
                .foregroundStyle(FAColor.ink)
                .focused($describeFocused)
                .padding(12)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous)
                        .strokeBorder(FAColor.separator, lineWidth: 1)
                }
                FAButton(title: String(localized: "food.describe.cta", defaultValue: "Analyse"), isEnabled: model.canDescribe) {
                    describeFocused = false
                    if let input = model.takeTextCapture() { capture.begin(input) }
                }
                Text(String(localized: "food.describe.hint", defaultValue: "The meal slot (breakfast, lunch, snack, dinner) follows the time of day."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkMuted)
            }
        }
    }

    @ViewBuilder
    private func history(_ content: FoodViewModel.Content) -> some View {
        let sections = model.sections(content)
        if sections.isEmpty {
            FACard {
                FAEmptyState(
                    title: String(localized: "food.empty.title", defaultValue: "No meals yet"),
                    message: String(localized: "food.empty.message", defaultValue: "Your first plate is one photo away."),
                    systemImage: "fork.knife"
                )
            }
        } else {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: FASpacing.sm) {
                    Text(section.title)
                        .font(FATypography.title)
                        .foregroundStyle(FAColor.ink)
                    ForEach(section.meals) { meal in
                        NavigationLink(value: Route.meal(meal.id)) {
                            MealCard(meal: meal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// The Food tab's meal card (Expo `LogMealCard`, C-1 design): name with the macros under it,
/// photo on the right in a bordered square, time greyed at the bottom.
struct MealCard: View {
    let meal: MealLog

    var body: some View {
        FACard {
            HStack(alignment: .top, spacing: FASpacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.displayName)
                        .font(FATypography.headline)
                        .foregroundStyle(FAColor.ink)
                        .lineLimit(2)
                    statusOrMacros
                    Text(Format.time(meal.loggedAt))
                        .font(FATypography.caption)
                        .foregroundStyle(FAColor.inkMuted)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                if meal.photoPath != nil {
                    MealPhotoView(path: meal.photoPath)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusOrMacros: some View {
        switch meal.status {
        case .queued, .identifying, .pricing:
            Label(String(localized: "meal.status.analyzing", defaultValue: "Analysing…"), systemImage: "sparkles")
                .font(FATypography.caption)
                .foregroundStyle(FAColor.accent)
        case .needsInput:
            Label(String(localized: "meal.status.needsInput", defaultValue: "Needs your input"), systemImage: "questionmark.circle")
                .font(FATypography.caption)
                .foregroundStyle(FAColor.warning)
        case .failed:
            Label(String(localized: "meal.status.failed", defaultValue: "Analysis failed"), systemImage: "exclamationmark.circle")
                .font(FATypography.caption)
                .foregroundStyle(FAColor.danger)
        case .complete:
            MacroLine(kcal: meal.totalCalories, protein: meal.totalProteinG, carbs: meal.totalCarbsG, fat: meal.totalFatG)
        }
    }
}

/// `420 kcal · P 18 C 60 F 12` in the locked macro palette.
struct MacroLine: View {
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?

    var body: some View {
        (Text(Format.kcal(kcal ?? 0)).foregroundColor(FAColor.accent).bold()
            + Text("  ·  ").foregroundColor(FAColor.inkMuted)
            + Text("P \(Int((protein ?? 0).rounded()))").foregroundColor(FAColor.protein).bold()
            + Text("   ").foregroundColor(FAColor.inkMuted)
            + Text("C \(Int((carbs ?? 0).rounded()))").foregroundColor(FAColor.carbs).bold()
            + Text("   ").foregroundColor(FAColor.inkMuted)
            + Text("F \(Int((fat ?? 0).rounded()))").foregroundColor(FAColor.fat).bold())
            .font(FATypography.caption)
            .accessibilityLabel(String(localized: "macros.a11y", defaultValue: "\(Int((kcal ?? 0).rounded())) kilocalories, protein \(Int((protein ?? 0).rounded())) grams, carbs \(Int((carbs ?? 0).rounded())) grams, fat \(Int((fat ?? 0).rounded())) grams"))
    }
}

/// Today's totals against the profile targets (`nb_patient_app_profiles.target_*`).
struct MacrosTodayCard: View {
    let meals: [MealLog]
    let profile: MemberProfile?

    private var kcal: Double { meals.compactMap(\.totalCalories).reduce(0, +) }
    private var protein: Double { meals.compactMap(\.totalProteinG).reduce(0, +) }
    private var carbs: Double { meals.compactMap(\.totalCarbsG).reduce(0, +) }
    private var fat: Double { meals.compactMap(\.totalFatG).reduce(0, +) }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.sm) {
                HStack {
                    Text(String(localized: "food.today.title", defaultValue: "Today so far"))
                        .font(FATypography.headline)
                        .foregroundStyle(FAColor.ink)
                    Spacer()
                    Text(String(localized: "food.today.count", defaultValue: "\(meals.count) meals"))
                        .font(FATypography.caption)
                        .foregroundStyle(FAColor.inkSecondary)
                }
                HStack(alignment: .top, spacing: FASpacing.sm) {
                    MacroStat(label: String(localized: "macros.energy", defaultValue: "Energy"), value: kcal, target: profile?.targetCalories, unit: "kcal", color: FAColor.kcal)
                    MacroStat(label: String(localized: "macros.protein", defaultValue: "Protein"), value: protein, target: profile?.targetProteinG, unit: "g", color: FAColor.protein)
                    MacroStat(label: String(localized: "macros.carbs", defaultValue: "Carbs"), value: carbs, target: profile?.targetCarbsG, unit: "g", color: FAColor.carbs)
                    MacroStat(label: String(localized: "macros.fat", defaultValue: "Fat"), value: fat, target: profile?.targetFatG, unit: "g", color: FAColor.fat)
                }
            }
        }
    }
}

private struct MacroStat: View {
    let label: String
    let value: Double
    let target: Int?
    let unit: String
    let color: Color

    private var fraction: Double {
        guard let target, target > 0 else { return 0 }
        return min(1, value / Double(target))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(FATypography.caption)
                .foregroundStyle(FAColor.inkSecondary)
            Text("\(Int(value.rounded()))")
                .font(FATypography.metric)
                .foregroundStyle(FAColor.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(target.map { String(localized: "macros.of", defaultValue: "of \($0) \(unit)") } ?? unit)
                .font(FATypography.caption)
                .foregroundStyle(FAColor.inkMuted)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18))
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(value.rounded())) \(unit)" + (target.map { ", \(String(localized: "macros.of", defaultValue: "of \($0) \(unit)"))" } ?? ""))
    }
}
