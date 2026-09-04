import SwiftUI

/// The eight mandatory screens (the Expo `ob-*`): welcome → baseline → activity (the ONE write) → energy →
/// nutrition → meals → check-ins → ready (stamps `onboarding_completed_at` on appear). Progress is kept
/// on the device (closing on screen 4 lands on screen 4); only completion is server-side.
struct OnboardingFlowView: View {
    @Environment(AppDependencies.self) private var dependencies
    let member: Member
    let onFinished: () -> Void
    @State private var model: OnboardingModel?

    var body: some View {
        Group {
            if let model {
                @Bindable var model = model
                NavigationStack(path: $model.path) {
                    OBWelcomeScreen(model: model)
                        .navigationDestination(for: OnboardingStep.self) { step in screen(step, model) }
                }
            } else {
                LaunchView()
            }
        }
        .onAppear {
            if model == nil { model = OnboardingModel(member: member, dependencies: dependencies, onFinished: onFinished) }
        }
    }

    @ViewBuilder
    private func screen(_ step: OnboardingStep, _ model: OnboardingModel) -> some View {
        switch step {
        case .welcome: OBWelcomeScreen(model: model)
        case .baseline: OBBaselineScreen(model: model)
        case .activity: OBActivityScreen(model: model)
        case .energy: OBEnergyScreen(model: model)
        case .nutrition: OBNutritionScreen(model: model)
        case .meals: OBMealsScreen(model: model)
        case .checkins: OBCheckinsScreen(model: model)
        case .ready: OBReadyScreen(model: model)
        }
    }
}

@MainActor
@Observable
final class OnboardingModel {
    let member: Member
    var draft: OnboardingDraft
    var path: [OnboardingStep]
    /// The profile as CM OS returned it after the activity write — the trigger's `tdee_kcal` lives here.
    var savedProfile: MemberProfile?
    var touched: Set<String> = []
    var saving = false
    var saveError: String?
    var stamping = false
    var stampFailed = false
    var stamped = false

    private let profile: ProfileService
    private let checkins: CheckinService
    private let onFinished: () -> Void

    init(member: Member, dependencies: AppDependencies, onFinished: @escaping () -> Void) {
        self.member = member
        self.profile = dependencies.profile
        self.checkins = dependencies.checkins
        self.onFinished = onFinished
        var d = OnboardingDraft.load(userId: member.userId)
        // The welcome screen's decision: the five already on the profile ⇒ the baseline is stepped over.
        d.knownBaseline = OnboardingLogic.baselineIsKnown(member.profile)
        if d.knownBaseline == false, d.sex == nil, let p = member.profile {
            // Known values pre-filled — nobody is asked to re-type what FunctionAlps already has.
            d.sex = p.sex?.rawValue
            d.age = p.age.map { "\($0)" } ?? ""
            d.height = p.heightCm.map(Self.format) ?? ""
            d.weight = p.weightKg.map(Self.format) ?? ""
            d.activity = p.activityLevel
        }
        self.draft = d
        // Resume at the high-water mark: every step up to it, minus the two the welcome skipped.
        self.path = OnboardingStep.allCases
            .filter { $0.rawValue >= 2 && $0.rawValue <= d.step }
            .filter { !(d.knownBaseline && ($0 == .baseline || $0 == .activity)) }
    }

    private static func format(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v) }

    private func persist() { draft.save(userId: member.userId) }

    // MARK: Navigation

    func next(after step: OnboardingStep) -> OnboardingStep {
        switch step {
        case .welcome: draft.knownBaseline ? .energy : .baseline
        case .baseline: .activity
        case .activity: .energy
        case .energy: .nutrition
        case .nutrition: .meals
        case .meals: .checkins
        case .checkins: .ready
        case .ready: .ready
        }
    }

    func advance(from step: OnboardingStep) {
        let to = next(after: step)
        path.append(to)
        draft.step = max(draft.step, to.rawValue)
        persist()
    }

    func back() { _ = path.popLast() }

    /// "Not right? Update" on the energy screen — plain flow mode, returns here through activity.
    func editBaseline() { path.append(.baseline) }

    // MARK: Baseline

    var sex: MemberProfile.Sex? {
        get { draft.sex.flatMap(MemberProfile.Sex.init(rawValue:)) }
        set { draft.sex = newValue?.rawValue; persist() }
    }
    var activity: ActivityLevel? {
        get { draft.activity.flatMap(ActivityLevel.init(rawValue:)) }
        set { draft.activity = newValue?.rawValue; persist() }
    }

    var bodyOk: Bool {
        sex != nil && !draft.age.isEmpty && !draft.height.isEmpty && !draft.weight.isEmpty
            && BaselineLogic.ageError(draft.age) == nil && BaselineLogic.heightError(draft.height) == nil && BaselineLogic.weightError(draft.weight) == nil
    }

    var values: BaselineValues? { BaselineLogic.resolve(sex: sex, age: draft.age, height: draft.height, weight: draft.weight, activity: activity) }

    /// The one write, once all five are known. A failed write never costs an answer — the draft holds them.
    func saveActivity() async {
        guard !saving, activity != nil else { return }
        persist()
        guard let values else {
            // A cleared draft could land here empty — collect them rather than write a partial row.
            path = path.filter { $0 != .activity } + [.baseline]
            return
        }
        saving = true
        saveError = nil
        do {
            savedProfile = try await profile.saveBaseline(patientId: member.patientId, values: values)
            advance(from: .activity)
        } catch {
            saveError = String(localized: "baseline.saveFailed", defaultValue: "We couldn't save that just now. Your answers are safe · try again.")
        }
        saving = false
    }

    /// DB first (it is the authority), the identical local formula second — the figure never jumps.
    var kcal: Int? {
        if let t = savedProfile?.tdeeKcal { return BaselineLogic.roundToNearest50(t) }
        if draft.knownBaseline, let t = member.profile?.tdeeKcal { return BaselineLogic.roundToNearest50(t) }
        if let values { return BaselineLogic.estimateKcal(values) }
        return nil
    }

    // MARK: Completion

    /// Stamped when the ready screen OPENS, not on a CTA: the member has now seen everything.
    func stamp() async {
        guard !stamping, !stamped else { return }
        stamping = true
        stampFailed = false
        do {
            _ = try await profile.completeOnboarding(patientId: member.patientId)
            stamped = true
            OnboardingDraft.clear(userId: member.userId)
        } catch {
            stampFailed = true
        }
        stamping = false
    }

    /// Hands the app a first thing to do, then lets the gate re-read the row (the DB stays the authority).
    func finish(_ intent: Intent) {
        switch intent {
        case .firstMeal: AppDelegate.pendingRoute = URL(string: "functionalps://food?capture=1")
        case .firstCheckin: AppDelegate.pendingRoute = URL(string: "functionalps://checkin/\(checkins.currentSlot.rawValue)")
        case .skip: AppDelegate.pendingRoute = nil
        }
        onFinished()
    }

    enum Intent { case firstMeal, firstCheckin, skip }
}

// MARK: - 1 · Welcome

private struct OBWelcomeScreen: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingScaffold(
            step: .welcome,
            eyebrow: String(localized: "ob.welcome.eyebrow", defaultValue: "Your FunctionAlps journey"),
            title: Text(String(localized: "ob.welcome.title", defaultValue: "Understand how food works for")) + Text(" ") + Text(String(localized: "ob.welcome.titleAccent", defaultValue: "you.")).font(.custom(FATypography.displayItalicFace, size: 30, relativeTo: .largeTitle)).foregroundColor(FAColor.forestSoft),
            primary: model.draft.knownBaseline
                ? String(localized: "action.continue", defaultValue: "Continue")
                : String(localized: "ob.welcome.cta", defaultValue: "Set up my profile"),
            onPrimary: { model.advance(from: .welcome) }
        ) {
            OBParagraph(String(localized: "ob.welcome.p1", defaultValue: "FunctionAlps helps us understand what you eat, when you eat it, and how your body responds.")).padding(.bottom, 10)
            OBParagraph(String(localized: "ob.welcome.p2", defaultValue: "By combining your meals with simple check-ins throughout the day, we can build a much clearer picture of your nutrition and daily wellbeing.")).padding(.bottom, 22)
            if model.draft.knownBaseline {
                FACard(padded: false) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(FAColor.forestSoft).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "ob.welcome.known.title", defaultValue: "We already have your details")).font(FATypography.sans(14.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            Text(String(localized: "ob.welcome.known.body", defaultValue: "From the questionnaire you completed · so we'll skip straight to what it means for your daily energy. You can change any of it afterwards."))
                                .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                        }
                    }
                    .padding(15)
                }
                .overlay { RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous).strokeBorder(FAColor.forestSoft, lineWidth: 1.5) }
                .padding(.bottom, 14)
            }
            VStack(spacing: 10) {
                OBIconCard(symbol: "camera", title: String(localized: "ob.welcome.eat.title", defaultValue: "What you eat"), line: String(localized: "ob.welcome.eat.body", defaultValue: "Photograph a meal and we turn it into real nutrition detail."))
                OBIconCard(symbol: "heart.text.square", title: String(localized: "ob.welcome.feel.title", defaultValue: "How you feel"), line: String(localized: "ob.welcome.feel.body", defaultValue: "Quick check-ins capture energy, digestion, mood and symptoms."))
                OBIconCard(symbol: "chart.line.uptrend.xyaxis", title: String(localized: "ob.welcome.fit.title", defaultValue: "How the two fit"), line: String(localized: "ob.welcome.fit.body", defaultValue: "Seen side by side over time, patterns start to show."))
            }
        }
    }
}

// MARK: - 2 · Baseline (body values — no write here)

private struct OBBaselineScreen: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focus: String?

    private var hadValues: Bool { model.member.profile?.age != nil || model.member.profile?.heightCm != nil }

    var body: some View {
        OnboardingScaffold(
            step: .baseline,
            eyebrow: String(localized: "ob.baseline.eyebrow", defaultValue: "Your baseline"),
            title: Text(hadValues
                ? String(localized: "ob.baseline.title.confirm", defaultValue: "Let's confirm your baseline.")
                : String(localized: "ob.baseline.title", defaultValue: "Let's understand your baseline.")),
            onBack: { model.back() },
            primary: String(localized: "action.continue", defaultValue: "Continue"),
            primaryEnabled: model.bodyOk,
            onPrimary: { focus = nil; model.advance(from: .baseline) },
            footnote: AnyView(Text(String(localized: "baseline.later", defaultValue: "You can update any of this later in your profile.")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).frame(maxWidth: .infinity))
        ) {
            OBParagraph(String(localized: "baseline.intro1", defaultValue: "We’ll start with a few basic measurements to estimate how much energy your body typically needs each day.")).padding(.bottom, 8)
            OBParagraph(String(localized: "baseline.intro2", defaultValue: "This gives us useful context when looking at your meals.")).padding(.bottom, 22)

            field(String(localized: "baseline.age", defaultValue: "How old are you?"), error: model.touched.contains("age") ? BaselineLogic.ageError(model.draft.age) : nil) {
                numberInput($model.draft.age, id: "age", placeholder: "e.g. 42", suffix: String(localized: "baseline.years", defaultValue: "years"), decimal: false)
            }
            field(String(localized: "baseline.sex", defaultValue: "Biological sex"), helper: String(localized: "baseline.sex.helper", defaultValue: "Used to estimate your energy requirements.")) {
                HStack(spacing: 10) {
                    chip(String(localized: "baseline.female", defaultValue: "Female"), selected: model.sex == .female) { model.sex = .female }
                    chip(String(localized: "baseline.male", defaultValue: "Male"), selected: model.sex == .male) { model.sex = .male }
                }
            }
            field(String(localized: "profile.height", defaultValue: "Height"), error: model.touched.contains("height") ? BaselineLogic.heightError(model.draft.height) : nil) {
                numberInput($model.draft.height, id: "height", placeholder: "e.g. 172", suffix: "cm", decimal: true)
            }
            field(String(localized: "baseline.weight", defaultValue: "Current weight"), error: model.touched.contains("weight") ? BaselineLogic.weightError(model.draft.weight) : nil) {
                numberInput($model.draft.weight, id: "weight", placeholder: "e.g. 68", suffix: "kg", decimal: true)
            }
        }
    }

    private func field<Content: View>(_ label: String, helper: String? = nil, error: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
            if let helper { Text(helper).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted) }
            content()
            if let error { Text(error).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red) }
        }
        .padding(.bottom, 22)
    }

    private func numberInput(_ text: Binding<String>, id: String, placeholder: String, suffix: String, decimal: Bool) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .focused($focus, equals: id)
                .onChange(of: focus) { _, now in if now != id, !text.wrappedValue.isEmpty { model.touched.insert(id) } }
                .font(FATypography.sans(16, relativeTo: .body)).foregroundStyle(FAColor.ink)
            Text(suffix).font(FATypography.sans(13.5, .medium, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 15)
        .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focus == id || !text.wrappedValue.isEmpty ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: focus == id ? 2 : 1) }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if selected { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                Text(label).font(FATypography.sans(14.5, .semibold, relativeTo: .subheadline))
            }
            .foregroundStyle(selected ? FAColor.forestSoft : FAColor.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? ProfilePalette.accentSoft : ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: selected ? 2 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 3 · Activity (the one write)

private struct OBActivityScreen: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingScaffold(
            step: .activity,
            eyebrow: String(localized: "ob.baseline.eyebrow", defaultValue: "Your baseline"),
            title: Text(String(localized: "ob.activity.title", defaultValue: "How active are you usually?")),
            onBack: { model.back() },
            primary: model.saving ? String(localized: "baseline.saving", defaultValue: "Saving…") : String(localized: "action.continue", defaultValue: "Continue"),
            primaryEnabled: model.activity != nil,
            primaryBusy: model.saving,
            onPrimary: { Task { await model.saveActivity() } },
            footnote: AnyView(Group {
                if let e = model.saveError {
                    Text(e).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4)
                } else {
                    Text(String(localized: "baseline.activity.footnote", defaultValue: "Pick the one that sounds most like a normal week.")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).frame(maxWidth: .infinity)
                }
            })
        ) {
            OBParagraph(String(localized: "baseline.activity.intro", defaultValue: "This is the last piece of the estimate. Don’t overthink it · an ordinary week is the right answer, not your best one.")).padding(.bottom, 22)
            VStack(spacing: 9) {
                ForEach(Array(ActivityLevel.allCases.enumerated()), id: \.element.id) { i, level in
                    ActivityCard(index: i, level: level, selected: model.activity == level) { model.activity = level }
                }
            }
        }
    }
}

// MARK: - 4 · Energy (a compass, not a score — PRD §21)

private struct OBEnergyScreen: View {
    let model: OnboardingModel

    var body: some View {
        if let kcal = model.kcal {
            OnboardingScaffold(
                step: .energy,
                eyebrow: String(localized: "baseline.energy.eyebrow", defaultValue: "Your energy needs"),
                title: Text(String(localized: "baseline.energy.title", defaultValue: "Your estimated daily energy target")),
                onBack: { model.back() },
                primary: String(localized: "action.continue", defaultValue: "Continue"),
                onPrimary: { model.advance(from: .energy) }
            ) {
                FACard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "safari").font(.system(size: 15, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                            Text(String(localized: "baseline.energy.compass", defaultValue: "Your energy compass").uppercased()).font(FATypography.sans(12, .semibold, relativeTo: .caption)).tracking(1.2).foregroundStyle(FAColor.forestSoft)
                        }
                        (Text("~\(kcal.formatted())").font(FATypography.display(38, relativeTo: .largeTitle)).foregroundColor(FAColor.ink)
                            + Text("  " + String(localized: "baseline.energy.unit", defaultValue: "kcal / day")).font(FATypography.sans(16, relativeTo: .body)).foregroundColor(ProfilePalette.muted))
                            .accessibilityLabel(String(localized: "baseline.energy.a11y", defaultValue: "About \(kcal) kilocalories per day"))
                        Text(String(localized: "baseline.energy.sub", defaultValue: "An estimate of your typical daily energy needs.")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                    }
                }
                .padding(.bottom, 18)
                HStack(spacing: 6) {
                    Text(model.draft.knownBaseline
                        ? String(localized: "ob.energy.fromKnown", defaultValue: "From the details you already gave us.")
                        : String(localized: "ob.energy.fromNew", defaultValue: "From the details you just gave us."))
                        .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                    Button { model.editBaseline() } label: {
                        Text(String(localized: "ob.energy.notRight", defaultValue: "Not right? Update")).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forestSoft)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 14)
                OBParagraph(String(localized: "baseline.energy.p1", defaultValue: "Based on your profile and activity level, this is our current estimate of how much energy your body uses in a typical day.")).padding(.bottom, 10)
                (Text(String(localized: "baseline.energy.p2a", defaultValue: "Think of it as a ")).foregroundColor(ProfilePalette.muted)
                    + Text(String(localized: "baseline.energy.p2b", defaultValue: "compass, not a score.")).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundColor(FAColor.ink)
                    + Text(" " + String(localized: "baseline.energy.p2c", defaultValue: "You don’t need to hit this number perfectly every day.")).foregroundColor(ProfilePalette.muted))
                    .font(FATypography.sans(15, relativeTo: .body)).lineSpacing(7).padding(.bottom, 20)
                FACard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "baseline.energy.made", defaultValue: "We’re much more interested in what those calories are made of · and how you respond to them."))
                            .font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(6)
                        FlowLayout(spacing: 7) {
                            OBChip(label: String(localized: "macros.proteins", defaultValue: "Proteins"), dot: FAColor.protein)
                            OBChip(label: String(localized: "macros.fats", defaultValue: "Fats"), dot: FAColor.fat)
                            OBChip(label: String(localized: "macros.carbohydrates", defaultValue: "Carbohydrates"), dot: FAColor.carbs)
                            OBChip(label: String(localized: "macros.fibres", defaultValue: "Fibres"), dot: FAColor.kcal)
                        }
                        Text(String(localized: "baseline.energy.alongside", defaultValue: "…alongside food quality, micronutrients, timing and meal composition."))
                            .font(FATypography.sans(13.5, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(6)
                        Text(String(localized: "baseline.energy.mostly", defaultValue: "And most importantly: how you feel, and the reactions or symptoms you notice around your food."))
                            .font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(6)
                    }
                }
                .padding(.bottom, 18)
                Text(String(localized: "baseline.energy.change", defaultValue: "Your energy needs can also change over time depending on your activity, body composition and goals. This number gives us useful context for interpreting the rest of your nutrition."))
                    .font(FATypography.sans(13.5, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(6)
            }
        } else {
            // Only reachable without a baseline (a cleared draft): ask for it rather than show an empty number.
            OnboardingScaffold(
                step: .energy,
                eyebrow: String(localized: "baseline.energy.eyebrow", defaultValue: "Your energy needs"),
                title: Text(String(localized: "ob.energy.missing.title", defaultValue: "We need your baseline first.")),
                onBack: { model.back() },
                primary: String(localized: "ob.energy.missing.cta", defaultValue: "Add my baseline"),
                onPrimary: { model.editBaseline() }
            ) {
                OBParagraph(String(localized: "ob.energy.missing.body", defaultValue: "Age, biological sex, height, weight and activity together give us the estimate. It takes about thirty seconds."))
            }
        }
    }
}

// MARK: - 5 · Nutrition

private struct OBNutritionScreen: View {
    let model: OnboardingModel

    private var items: [String] {
        [
            String(localized: "ob.nutrition.i1", defaultValue: "Protein, carbohydrates and fats"),
            String(localized: "ob.nutrition.i2", defaultValue: "Fibre"),
            String(localized: "ob.nutrition.i3", defaultValue: "Vitamins and minerals"),
            String(localized: "ob.nutrition.i4", defaultValue: "Food quality and composition"),
            String(localized: "ob.nutrition.i5", defaultValue: "Types of carbohydrates and fats"),
            String(localized: "ob.nutrition.i6", defaultValue: "Meal timing"),
            String(localized: "ob.nutrition.i7", defaultValue: "How foods are combined"),
            String(localized: "ob.nutrition.i8", defaultValue: "Your overall eating patterns"),
        ]
    }

    var body: some View {
        OnboardingScaffold(
            step: .nutrition,
            eyebrow: String(localized: "ob.nutrition.eyebrow", defaultValue: "Your nutrition"),
            title: Text(String(localized: "ob.nutrition.title", defaultValue: "We look beyond calories.")),
            onBack: { model.back() },
            primary: String(localized: "action.continue", defaultValue: "Continue"),
            onPrimary: { model.advance(from: .nutrition) }
        ) {
            OBParagraph(String(localized: "ob.nutrition.p1", defaultValue: "Two meals with the same number of calories can be very different.")).padding(.bottom, 18)
            FACard {
                VStack(alignment: .leading, spacing: 9) {
                    Text(String(localized: "ob.nutrition.lookAt", defaultValue: "We look at")).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).padding(.bottom, 3)
                    ForEach(items, id: \.self) { item in bullet(item, strong: false) }
                    bullet(String(localized: "ob.nutrition.feel", defaultValue: "And, importantly, how you feel afterwards"), strong: true)
                }
            }
            .padding(.bottom, 16)
            Text(String(localized: "ob.nutrition.p2", defaultValue: "The goal is to understand your nutrition as a whole · not reduce food to a number."))
                .font(FATypography.sans(14.5, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(6)
        }
    }

    private func bullet(_ text: String, strong: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(FAColor.forestSoft).frame(width: 5, height: 5).padding(.top, 7)
            Text(text).font(FATypography.sans(14, strong ? .semibold : .regular, relativeTo: .subheadline)).foregroundStyle(strong ? FAColor.ink : ProfilePalette.muted).lineSpacing(5)
        }
    }
}

// MARK: - 6 · Meals

private struct OBMealsScreen: View {
    let model: OnboardingModel

    private var steps: [(String, String)] {
        [
            ("camera", String(localized: "ob.meals.s1", defaultValue: "Take a photo")),
            ("viewfinder", String(localized: "ob.meals.s2", defaultValue: "AI identifies the foods")),
            ("fork.knife", String(localized: "ob.meals.s3", defaultValue: "Ingredients are structured")),
            ("sparkles", String(localized: "ob.meals.s4", defaultValue: "Nutritional information is estimated")),
            ("clock.arrow.circlepath", String(localized: "ob.meals.s5", defaultValue: "The meal becomes part of your nutrition history")),
        ]
    }

    var body: some View {
        OnboardingScaffold(
            step: .meals,
            eyebrow: String(localized: "ob.meals.eyebrow", defaultValue: "Meal logging"),
            title: Text(String(localized: "ob.meals.title", defaultValue: "Just take a photo.")),
            onBack: { model.back() },
            primary: String(localized: "ob.meals.cta", defaultValue: "Got it"),
            onPrimary: { model.advance(from: .meals) }
        ) {
            OBParagraph(String(localized: "ob.meals.p1", defaultValue: "When you eat, take a photo of your meal in the app. Our AI analyses the image, identifies the foods and ingredients, and creates a structured meal entry for you.")).padding(.bottom, 20)
            FACard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 13) {
                            VStack(spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ProfilePalette.accentSoft)
                                    Image(systemName: s.0).font(.system(size: 15, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                                }
                                .frame(width: 34, height: 34)
                                if i < steps.count - 1 { Rectangle().fill(ProfilePalette.hairline).frame(width: 1.5).frame(minHeight: 16) }
                            }
                            .frame(width: 34)
                            Text(s.1).font(FATypography.sans(14, .medium, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(5)
                                .padding(.top, 8).padding(.bottom, i < steps.count - 1 ? 14 : 0)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 16)
            FACard(padded: false) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "pencil").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.forestSoft).padding(.top, 2)
                    Text(String(localized: "ob.meals.correct", defaultValue: "You’ll always be able to review and correct the meal if something isn’t right · change a food, remove one, or add what we missed."))
                        .font(FATypography.sans(13.5, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(6)
                }
                .padding(15)
            }
        }
    }
}

// MARK: - 7 · Check-ins (language rule PRD §11: a reported response in time, never "food X caused Y")

private struct OBCheckinsScreen: View {
    let model: OnboardingModel

    private var captures: [String] {
        [
            String(localized: "ob.checkins.c1", defaultValue: "Energy"), String(localized: "ob.checkins.c2", defaultValue: "Mood"),
            String(localized: "ob.checkins.c3", defaultValue: "Stress"), String(localized: "ob.checkins.c4", defaultValue: "Sleep"),
            String(localized: "ob.checkins.c5", defaultValue: "Digestion"), String(localized: "ob.checkins.c6", defaultValue: "Symptoms"),
            String(localized: "ob.checkins.c7", defaultValue: "Overall wellbeing"),
        ]
    }
    private var symptoms: [String] {
        [
            String(localized: "ob.checkins.s1", defaultValue: "Bloating"), String(localized: "ob.checkins.s2", defaultValue: "Acid reflux"),
            String(localized: "ob.checkins.s3", defaultValue: "Gas"), String(localized: "ob.checkins.s4", defaultValue: "Digestive discomfort"),
            String(localized: "ob.checkins.s5", defaultValue: "Tiredness"), String(localized: "ob.checkins.s6", defaultValue: "Energy dip"),
            String(localized: "ob.checkins.s7", defaultValue: "Brain fog"), String(localized: "ob.checkins.s8", defaultValue: "Headache"),
            String(localized: "ob.checkins.s9", defaultValue: "Cravings"), String(localized: "ob.checkins.s10", defaultValue: "Low mood"),
        ]
    }
    private var cadence: [(String, String, String)] {
        [
            (String(localized: "ob.checkins.cad1.tag", defaultValue: "At least once a day"), String(localized: "ob.checkins.cad1.title", defaultValue: "Your daily baseline"), String(localized: "ob.checkins.cad1.body", defaultValue: "Try to complete at least one functional check-in every day.")),
            (String(localized: "ob.checkins.cad2.tag", defaultValue: "Around meals"), String(localized: "ob.checkins.cad2.title", defaultValue: "Even better"), String(localized: "ob.checkins.cad2.body", defaultValue: "When you can, check in around or after meals so we can better understand how you respond.")),
            (String(localized: "ob.checkins.cad3.tag", defaultValue: "When something changes"), String(localized: "ob.checkins.cad3.title", defaultValue: "Capture the moment"), String(localized: "ob.checkins.cad3.body", defaultValue: "If you notice a symptom or a clear change in how you feel, add it when it happens.")),
        ]
    }

    var body: some View {
        OnboardingScaffold(
            step: .checkins,
            eyebrow: String(localized: "ob.checkins.eyebrow", defaultValue: "Meals + check-ins"),
            title: Text(String(localized: "ob.checkins.title", defaultValue: "What you eat is only half the picture.")),
            onBack: { model.back() },
            primary: String(localized: "action.continue", defaultValue: "Continue"),
            onPrimary: { model.advance(from: .checkins) }
        ) {
            (Text(String(localized: "ob.checkins.p1a", defaultValue: "Your meals tell us what went in. Your check-ins help us understand")).foregroundColor(ProfilePalette.muted)
                + Text(" " + String(localized: "ob.checkins.p1b", defaultValue: "how you felt before and afterwards.")).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundColor(FAColor.ink))
                .font(FATypography.sans(15, relativeTo: .body)).lineSpacing(7).padding(.bottom, 10)
            OBParagraph(String(localized: "ob.checkins.p2", defaultValue: "Throughout the day you can quickly tell us how you’re feeling, and record symptoms or reactions you notice.")).padding(.bottom, 18)

            FACard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        Image(systemName: "waveform.path.ecg").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                        Text(String(localized: "ob.checkins.cover", defaultValue: "A check-in can cover")).font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    }
                    FlowLayout(spacing: 7) { ForEach(captures, id: \.self) { OBChip(label: $0) } }
                    Text(String(localized: "ob.checkins.slots", defaultValue: "Morning, midday and evening ask slightly different things · sleep, for instance, is only ever a morning question."))
                        .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                }
            }
            .padding(.bottom, 14)

            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "ob.checkins.notice.title", defaultValue: "Notice something after eating?")).font(FATypography.display(20, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                    Text(String(localized: "ob.checkins.notice.tell", defaultValue: "Tell us.")).font(FATypography.sans(14.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forestSoft)
                    Text(String(localized: "ob.checkins.notice.body", defaultValue: "If you experience a symptom or a noticeable change after a meal, log what happened and how strong it felt."))
                        .font(FATypography.sans(13.5, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(6).padding(.bottom, 4)
                    FlowLayout(spacing: 6) { ForEach(symptoms, id: \.self) { OBChip(label: $0, muted: true) } }
                }
            }
            .overlay { RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous).strokeBorder(FAColor.forestSoft, lineWidth: 1.5) }
            .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(ProfilePalette.muted).padding(.top, 2)
                Text(String(localized: "ob.checkins.guard", defaultValue: "We record what you noticed and when · a meal, then how you felt. That’s context for you and your nutritionist to read together, not a verdict that a food caused a symptom."))
                    .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
            }
            .padding(.horizontal, 2).padding(.bottom, 20)

            VStack(spacing: 10) {
                ForEach(Array(cadence.enumerated()), id: \.offset) { _, c in
                    FACard(padded: false) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.0.uppercased()).font(FATypography.sans(11, .semibold, relativeTo: .caption2)).tracking(1).foregroundStyle(FAColor.forestSoft).padding(.bottom, 2)
                            Text(c.1).font(FATypography.sans(14.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            Text(c.2).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                        }
                        .padding(15)
                    }
                }
            }
            .padding(.bottom, 18)

            (Text(String(localized: "ob.checkins.p3a", defaultValue: "You don’t need to be perfect.")).foregroundColor(ProfilePalette.muted)
                + Text(" " + String(localized: "ob.checkins.p3b", defaultValue: "Consistency gives us the clearest picture.")).font(FATypography.sans(14.5, .semibold, relativeTo: .body)).foregroundColor(FAColor.ink))
                .font(FATypography.sans(14.5, relativeTo: .body)).lineSpacing(6)
        }
    }
}

// MARK: - 8 · Ready (stamps on appear)

private struct OBReadyScreen: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingScaffold(
            step: .ready,
            eyebrow: String(localized: "ob.ready.eyebrow", defaultValue: "You’re ready"),
            title: Text(String(localized: "ob.ready.title", defaultValue: "For now, focus on two things.")),
            onBack: { model.back() },
            primary: String(localized: "ob.ready.firstMeal", defaultValue: "Log my first meal"),
            onPrimary: { model.finish(.firstMeal) },
            secondary: String(localized: "ob.ready.firstCheckin", defaultValue: "Do my first check-in"),
            onSecondary: { model.finish(.firstCheckin) },
            footnote: AnyView(Group {
                if model.stampFailed {
                    VStack(spacing: 6) {
                        Text(String(localized: "ob.ready.stampFailed", defaultValue: "We couldn’t save that you’ve finished setting up. Nothing you entered is lost."))
                            .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).multilineTextAlignment(.center).lineSpacing(4)
                        Button { Task { await model.stamp() } } label: {
                            Text(model.stamping ? String(localized: "ob.ready.trying", defaultValue: "Trying…") : String(localized: "action.retry", defaultValue: "Try again"))
                                .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forestSoft)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button { model.finish(.skip) } label: {
                        Text(String(localized: "ob.ready.skip", defaultValue: "Skip for now")).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                            .frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            })
        ) {
            OBIconCard(symbol: "camera", title: String(localized: "ob.ready.meals.title", defaultValue: "Photograph your meals"), line: String(localized: "ob.ready.meals.body", defaultValue: "We’ll help turn them into useful nutrition information."))
                .padding(.bottom, 11)
            OBIconCard(symbol: "heart.text.square", title: String(localized: "ob.ready.checkin.title", defaultValue: "Check in with how you feel"), line: String(localized: "ob.ready.checkin.body", defaultValue: "Especially when you notice symptoms or changes around your meals."))
                .padding(.bottom, 18)
            Text(String(localized: "ob.ready.p1", defaultValue: "The more context we have, the better we can understand your nutrition, your patterns and your individual experience."))
                .font(FATypography.sans(14.5, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(6)
        }
        .task { await model.stamp() }
    }
}
