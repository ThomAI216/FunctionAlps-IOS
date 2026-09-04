import SwiftUI

/// The Expo `(screens)/nutrition-macros.tsx` editing state: the body inputs, the goal, the member's
/// hand-tuned overrides, and the DB-authoritative targets read back after Validate. The instant
/// preview (`NutritionMath`) shows while editing; the stored row shows once validated.
@MainActor
@Observable
final class NutritionTargetsModel {
    typealias Goal = MemberProfile.GoalMode

    private(set) var member: Member?
    private(set) var meals: [MealLog] = []
    private(set) var loaded = false

    // Inputs (the profile row; the screen's fallbacks 72 / 175 / 34 are never persisted).
    var sex: MemberProfile.Sex = .male
    var age: Int?
    var heightCm: Double?
    var weightKg: Double?
    var bodyFat: Double?
    var activity: ActivityLevel?
    var goal: Goal = .maintain
    var customOffset: Int?
    var customProtein: Int?
    var customCarbs: Int?
    var customFat: Int?
    var mealsPerDay: Int?
    var snacksPerDay: Int?

    private(set) var dirty = false
    private(set) var saving = false
    private(set) var saved = false
    private(set) var saveError: String?
    private var savedTask: Task<Void, Never>?

    /// The stored targets (`target_*`, `tdee_kcal`) — shown when not editing and complete.
    private(set) var stored: (tdee: Int?, calories: Int?, protein: Int?, carbs: Int?, fat: Int?)?

    func load(_ dependencies: AppDependencies) async {
        if let member = try? await dependencies.members.currentMember() {
            self.member = member
            meals = (try? await dependencies.meals.recentMeals(patientId: member.patientId)) ?? []
            apply(member.profile)
        }
        loaded = true
    }

    private func apply(_ p: MemberProfile?) {
        guard let p else { return }
        sex = p.sex == .female ? .female : .male
        age = p.age
        heightCm = p.heightCm
        weightKg = p.weightKg
        bodyFat = p.estimatedBodyFatPercent
        activity = p.activityLevel.flatMap(ActivityLevel.init(rawValue:))
        goal = p.goalMode ?? NutritionMath.goal(fromHealthGoals: p.healthGoals)
        customOffset = p.customCalorieOffsetKcal
        mealsPerDay = p.mealsPerDay
        snacksPerDay = p.snacksPerDay
        if p.macrosCustomized {
            customProtein = p.targetProteinG
            customCarbs = p.targetCarbsG
            customFat = p.targetFatG
        } else {
            customProtein = nil; customCarbs = nil; customFat = nil
        }
        stored = (p.tdeeKcal.map { Int($0) }, p.targetCalories, p.targetProteinG, p.targetCarbsG, p.targetFatG)
    }

    var hasBodyData: Bool { weightKg != nil && heightCm != nil }

    // Preview values (fallbacks keep the maths alive on a half-filled row).
    var weightValue: Double { weightKg ?? 72 }
    var heightValue: Double { heightCm ?? 175 }
    var ageValue: Int { age ?? 34 }
    var bodyFatForGoal: Double { bodyFat ?? 22 }

    var tdee: Int { NutritionMath.tdee(weightKg: weightValue, heightCm: heightValue, age: ageValue, sex: sex, activity: activity ?? .moderatelyActive, bodyFatPercent: bodyFat) }
    var activeOffset: Int { customOffset ?? NutritionMath.goalOffset(goal: goal, bodyFatPercent: bodyFatForGoal) }
    var goalCalories: Int { tdee + activeOffset }
    var isCustom: Bool { customProtein != nil || customCarbs != nil || customFat != nil }

    var macroTargets: NutritionMath.MacroTargets {
        var t = NutritionMath.goalMacros(tdee: tdee, weightKg: weightValue, sex: sex, goal: goal, bodyFatPercent: bodyFat)
        if let customProtein { t.proteinG = customProtein }
        if let customCarbs { t.carbsG = customCarbs }
        if let customFat { t.fatG = customFat }
        return t
    }

    /// DB values only when calories + all three macros are present, and only while not editing.
    private var storedReady: (tdee: Int?, calories: Int, protein: Int, carbs: Int, fat: Int)? {
        guard !dirty, let s = stored, let c = s.calories, let p = s.protein, let cb = s.carbs, let f = s.fat else { return nil }
        return (s.tdee, c, p, cb, f)
    }
    var displayMacros: NutritionMath.MacroTargets {
        if let s = storedReady { return NutritionMath.MacroTargets(proteinG: s.protein, carbsG: s.carbs, fatG: s.fat, calories: s.calories) }
        return macroTargets
    }
    var displayTdee: Int { storedReady?.tdee ?? tdee }
    var displayGoalCalories: Int { storedReady?.calories ?? goalCalories }

    var loggedMeals: Int { meals.filter { $0.mealType != .snack }.count }
    var loggedSnacks: Int { meals.filter { $0.mealType == .snack }.count }
    var mealsCount: Int { mealsPerDay.map { min(6, max(1, $0)) } ?? max(loggedMeals, 3) }
    var snacksCount: Int { snacksPerDay.map { min(4, max(0, $0)) } ?? max(0, loggedSnacks) }

    var consumedFiber: Double { meals.reduce(0) { $0 + ($1.totalFiberG ?? $1.micros["fiber_g"] ?? 0) } }
    var fiberTarget: Int { NutritionMath.fiberTarget(calories: displayMacros.calories) }

    // MARK: Edits

    func touch() { dirty = true; saved = false }

    func setGoal(_ g: Goal) {
        goal = g
        customOffset = nil
        customProtein = nil; customCarbs = nil; customFat = nil
        touch()
    }

    func setProteinPerKg(_ gPerKg: Double) { customProtein = Int((weightValue * gPerKg).rounded()); touch() }
    func setFatPercent(_ pct: Double) { customFat = Int((Double(goalCalories) * (pct / 100) / 9).rounded()); touch() }
    func nudgeCarbs(_ delta: Int) { customCarbs = max(0, macroTargets.carbsG + delta); touch() }

    // MARK: Validate

    func validate(_ dependencies: AppDependencies) async {
        guard let member, let heightCm, let weightKg else { return }
        saving = true
        saveError = nil
        let t = macroTargets
        let write = NutritionProfileWrite(
            appSex: sex.rawValue, appAge: age, appHeightCm: heightCm, appWeightKg: weightKg,
            estimatedBodyFatPercent: bodyFat, activityLevel: activity?.rawValue, goalMode: goal.rawValue,
            macrosCustomized: isCustom, mealsPerDay: mealsPerDay, snacksPerDay: snacksPerDay, customCalorieOffsetKcal: customOffset,
            targetCalories: isCustom ? t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9 : nil,
            targetProteinG: isCustom ? t.proteinG : nil, targetCarbsG: isCustom ? t.carbsG : nil, targetFatG: isCustom ? t.fatG : nil,
            tdeeKcal: isCustom ? tdee : nil
        )
        do {
            let profile = try await dependencies.profile.saveNutritionProfile(patientId: member.patientId, profile: write)
            dirty = false
            if let profile {
                self.member = Member(userId: member.userId, patientId: member.patientId, email: member.email, displayName: member.displayName, profile: profile)
                apply(profile)
            }
            saved = true
            savedTask?.cancel()
            savedTask = Task { try? await Task.sleep(for: .seconds(2.5)); saved = false }
        } catch let error as AppError {
            saveError = error.userMessage
        } catch {
            saveError = String(localized: "targets.saveFailed", defaultValue: "Your changes couldn't be saved. Try again.")
        }
        saving = false
    }
}

// MARK: - Screen

/// The Expo `nutrition-macros`: profile summary, calorie target, macro targets, meals & snacks, and
/// the three macro explainers. Local until Validate; the DB trigger owns the stored targets.
struct NutritionTargetsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model = NutritionTargetsModel()
    @State private var expandedMacro: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.loaded {
                FALoadingState().padding(.top, 60)
                Spacer()
            } else if !model.hasBodyData {
                setupPrompt
                Spacer()
            } else {
                banner
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ProfileSummaryCard(model: model)
                        CalorieTargetCard(model: model)
                        MacroTargetsCard(model: model)
                        MealsSnacksCard(model: model)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(localized: "targets.edu.title", defaultValue: "Understanding the 3 macros")).font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                            ForEach(MacroEducation.entries) { entry in
                                MacroInfoCard(entry: entry, expanded: expandedMacro == entry.key) {
                                    withAnimation(.spring(duration: 0.3)) { expandedMacro = expandedMacro == entry.key ? nil : entry.key }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, FASpacing.navBarClearance)
                }
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load(dependencies) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { router.pop() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)).foregroundStyle(FAColor.ink)
                    .frame(width: 40, height: 40)
                    .background(ProfilePalette.surface, in: Circle())
                    .overlay { Circle().strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "targets.title", defaultValue: "Macros & Nutrition")).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                Text(String(localized: "targets.subtitle", defaultValue: "Your personalized macro dashboard")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
    }

    /// The Expo Day-2 redirect (`nutrition-setup`): on the phone the baseline editor collects the body data.
    private var setupPrompt: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "targets.setup.title", defaultValue: "Start with your baseline")).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                Text(String(localized: "targets.setup.body", defaultValue: "Your height, weight, age and activity level give the energy estimate every target is built on. Add them once; you can tune everything here afterwards."))
                    .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                ForestPillButton(title: String(localized: "targets.setup.cta", defaultValue: "Set up my baseline")) { router.push(.baseline) }.padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var banner: some View {
        if model.saved {
            HStack(spacing: 8) {
                Text("✓")
                Text(String(localized: "targets.validated", defaultValue: "Your changes have been validated.")).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(Color(hex: 0x065F46))
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xD1FAE5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16).padding(.bottom, 8)
        } else if model.dirty {
            HStack {
                Text(String(localized: "targets.dirty", defaultValue: "Changes are local. Validate to save them.")).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(Color(hex: 0x92400E))
                Spacer(minLength: 12)
                Button { Task { await model.validate(dependencies) } } label: {
                    Text(model.saving ? String(localized: "targets.saving", defaultValue: "Saving…") : String(localized: "targets.validate", defaultValue: "Validate"))
                        .font(FATypography.sans(13, .semibold, relativeTo: .caption)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(Color(hex: 0xD97706), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain).disabled(model.saving)
            }
            .padding(12)
            .background(Color(hex: 0xFEF3C7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        if let error = model.saveError {
            Text(error).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).padding(.horizontal, 18).padding(.bottom, 8)
        }
    }
}

// MARK: - Profile summary

private struct ProfileSummaryCard: View {
    @Bindable var model: NutritionTargetsModel
    @State private var expanded = false
    @State private var wheel: WheelField?
    @State private var activityOpen = false

    enum WheelField: String, Identifiable { case age, height, weight, bodyFat; var id: String { rawValue } }

    private var sexLabel: String { model.sex == .male ? String(localized: "sex.male", defaultValue: "Male") : String(localized: "sex.female", defaultValue: "Female") }
    private var activityLabel: String { (model.activity ?? .moderatelyActive).title }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            MicroLabel(text: String(localized: "targets.profile", defaultValue: "Your Profile"), color: FAColor.forestSoft)
                            if expanded {
                                Text(String(localized: "targets.profile.tap", defaultValue: "Tap to update your metrics")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                            } else {
                                Text("\(sexLabel) · \(model.ageValue)y · \(Int(model.heightValue))cm · \(NutrientFormat.amount(model.weightValue))kg · \(model.bodyFat.map { "\(NutrientFormat.amount($0))% BF" } ?? "BF ·") · \(activityLabel)")
                                    .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(ProfilePalette.muted).rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        readOnlyField(String(localized: "targets.field.sex", defaultValue: "Sex"), value: sexLabel)
                        wheelField(String(localized: "targets.field.age", defaultValue: "Age"), display: String(localized: "targets.value.years", defaultValue: "\(model.ageValue) years"), field: .age)
                        wheelField(String(localized: "targets.field.height", defaultValue: "Height"), display: "\(Int(model.heightValue)) cm", field: .height)
                        wheelField(String(localized: "targets.field.weight", defaultValue: "Weight"), display: "\(NutrientFormat.amount(model.weightValue)) kg", field: .weight)
                        wheelField(String(localized: "targets.field.bodyFat", defaultValue: "Body Fat"), display: model.bodyFat.map { "\(NutrientFormat.amount($0))%" } ?? String(localized: "targets.value.notSet", defaultValue: "Not set"), field: .bodyFat)
                    }
                    .padding(.top, 14)
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel(String(localized: "targets.field.activity", defaultValue: "Activity Level"))
                        Button { activityOpen = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(activityLabel).font(FATypography.sans(15, .bold, relativeTo: .body)).foregroundStyle(FAColor.forestSoft)
                                    Text((model.activity ?? .moderatelyActive).body).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.forestSoft).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 12)
                            .background(ProfilePalette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FAColor.forestSoft, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 12)
                }
            }
        }
        .sheet(item: $wheel) { field in
            wheelSheet(field)
        }
        .sheet(isPresented: $activityOpen) {
            ActivityPickerSheet(selected: model.activity ?? .moderatelyActive) { level in
                model.activity = level; model.touch(); activityOpen = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(FATypography.sans(11, .semibold, relativeTo: .caption2)).tracking(0.5).foregroundStyle(ProfilePalette.muted)
    }

    private func readOnlyField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) { fieldLabel(label); Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(ProfilePalette.muted) }
            Text(value).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(ProfilePalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 12)
                .background(ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
        }
    }

    private func wheelField(_ label: String, display: String, field: WheelField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label)
            Button { wheel = field } label: {
                Text(display).font(FATypography.sans(15, .bold, relativeTo: .body)).foregroundStyle(FAColor.forestSoft)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 12)
                    .background(ProfilePalette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FAColor.forestSoft, lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func wheelSheet(_ field: WheelField) -> some View {
        switch field {
        case .age:
            WheelPickerSheet(title: String(localized: "targets.field.age", defaultValue: "Age"), value: Double(model.ageValue), range: 10...100, step: 1, unit: String(localized: "targets.unit.years", defaultValue: "years"), onConfirm: { v in model.age = Int(v); model.touch() })
        case .height:
            WheelPickerSheet(title: String(localized: "targets.field.height", defaultValue: "Height"), value: model.heightValue, range: 100...220, step: 1, unit: "cm", onConfirm: { v in model.heightCm = v; model.touch() })
        case .weight:
            WheelPickerSheet(title: String(localized: "targets.field.weight", defaultValue: "Weight"), value: model.weightValue, range: 30...200, step: 0.5, unit: "kg", onConfirm: { v in model.weightKg = v; model.touch() })
        case .bodyFat:
            WheelPickerSheet(title: String(localized: "targets.field.bodyFatFull", defaultValue: "Body Fat %"), value: model.bodyFat ?? 18, range: 5...55, step: 0.5, unit: "%", onConfirm: { v in model.bodyFat = v; model.touch() })
        }
    }
}

/// The Expo `WheelPickerSheet`: a single wheel over a stepped range, confirm or cancel.
struct WheelPickerSheet: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit: String = ""
    var format: ((Double) -> String)? = nil
    let onConfirm: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Double = 0

    private var values: [Double] {
        var out: [Double] = []
        var v = range.lowerBound
        while v <= range.upperBound + 0.0001 { out.append((v * 100).rounded() / 100); v += step }
        return out
    }

    private func label(_ v: Double) -> String {
        if let format { return format(v) }
        let n = v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
        return unit.isEmpty ? n : "\(n) \(unit)"
    }

    var body: some View {
        VStack(spacing: 8) {
            Capsule().fill(ProfilePalette.hairline).frame(width: 40, height: 4).padding(.top, 10)
            Text(title).font(FATypography.display(16, relativeTo: .body)).foregroundStyle(FAColor.ink).padding(.top, 6)
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { v in
                    Text(label(v)).font(FATypography.sans(17, .semibold, relativeTo: .body)).tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 180)
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text(String(localized: "common.cancel", defaultValue: "Cancel")).font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(ProfilePalette.surfaceSoft, in: Capsule()).overlay { Capsule().strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                Button { onConfirm(selection); dismiss() } label: {
                    Text(String(localized: "action.confirm", defaultValue: "Confirm")).font(FATypography.sans(14, .bold, relativeTo: .body)).foregroundStyle(FAColor.charcoal)
                        .frame(maxWidth: .infinity).padding(.vertical, 13).background(FAColor.forestSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(FAColor.warm)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
        .onAppear { selection = values.min(by: { abs($0 - value) < abs($1 - value) }) ?? value }
    }
}

private struct ActivityPickerSheet: View {
    let selected: ActivityLevel
    let onPick: (ActivityLevel) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(ProfilePalette.hairline).frame(width: 40, height: 4).padding(.top, 10).padding(.bottom, 12)
            Text(String(localized: "targets.field.activity", defaultValue: "Activity Level")).font(FATypography.display(16, relativeTo: .body)).foregroundStyle(FAColor.ink).padding(.bottom, 8)
            ForEach(Array(ActivityLevel.allCases.enumerated()), id: \.element.id) { index, level in
                Button { onPick(level) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.title).font(FATypography.sans(15, .bold, relativeTo: .body)).foregroundStyle(level == selected ? FAColor.forestSoft : FAColor.ink)
                            Text(level.body).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                        }
                        Spacer()
                        if level == selected { Circle().fill(FAColor.forestSoft).frame(width: 10, height: 10) }
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) { if index < ActivityLevel.allCases.count - 1 { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(FAColor.warm)
    }
}

// MARK: - Calorie target

private struct CalorieTargetCard: View {
    @Bindable var model: NutritionTargetsModel
    @State private var offsetOpen = false

    private var proteinPct: Int { let t = total; return t > 0 ? Int((Double(model.displayMacros.proteinG * 4) / Double(t) * 100).rounded()) : 0 }
    private var fatPct: Int { let t = total; return t > 0 ? Int((Double(model.displayMacros.fatG * 9) / Double(t) * 100).rounded()) : 0 }
    private var carbsPct: Int { max(0, 100 - proteinPct - fatPct) }
    private var total: Int { model.displayMacros.proteinG * 4 + model.displayMacros.carbsG * 4 + model.displayMacros.fatG * 9 }
    private var extreme: Bool { model.activeOffset < -500 || model.activeOffset > 500 }

    private func offsetText(_ o: Int) -> String { o == 0 ? "±0 kcal" : "\(o > 0 ? "+" : "")\(o) kcal" }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel(text: String(localized: "targets.calorie", defaultValue: "Calorie Target"), color: FAColor.forestSoft).padding(.bottom, 10)
                HStack(spacing: 0) {
                    ForEach([NutritionMath.Goal.build, .maintain, .cut], id: \.rawValue) { g in
                        Button { model.setGoal(g) } label: {
                            Text(goalLabel(g)).font(FATypography.sans(13, .semibold, relativeTo: .caption))
                                .foregroundStyle(model.goal == g ? FAColor.cream : ProfilePalette.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(model.goal == g ? FAColor.forestSoft : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
                .padding(.bottom, 14)

                HStack(alignment: .center, spacing: 6) {
                    Text(String(localized: "targets.tdee", defaultValue: "TDEE")).font(FATypography.sans(13, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                    Text("\(model.displayTdee)").font(FATypography.sans(15, .bold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    if model.goal != .maintain {
                        Button { offsetOpen = true } label: {
                            Text(offsetText(model.activeOffset)).font(FATypography.sans(13, .semibold, relativeTo: .caption))
                                .foregroundStyle(extreme ? FAColor.goldSoft : FAColor.forestSoft)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(extreme ? Color(hex: 0xFDE074, opacity: 0.18) : ProfilePalette.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(extreme ? Color(hex: 0xFDE074, opacity: 0.45) : ProfilePalette.hairline, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("=").font(FATypography.sans(13, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                    Text("\(model.displayGoalCalories)").font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.forestSoft)
                    Text(String(localized: "targets.kcalDay", defaultValue: "kcal/day")).font(FATypography.sans(13, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                }

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(hex: FoodPalette.pastel["protein"]!)).frame(width: geo.size.width * CGFloat(proteinPct) / 100)
                        Rectangle().fill(Color(hex: FoodPalette.pastel["carbs"]!)).frame(width: geo.size.width * CGFloat(carbsPct) / 100)
                        Rectangle().fill(Color(hex: FoodPalette.pastel["fat"]!))
                    }
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.4)).frame(height: 1.5) }
                }
                .frame(height: 10).clipShape(Capsule()).padding(.top, 14)
                HStack {
                    Text("\(String(localized: "macros.protein", defaultValue: "Protein")) \(proteinPct)%").foregroundStyle(Color(hex: FoodPalette.label["protein"]!))
                    Spacer()
                    Text("\(String(localized: "macros.carbs", defaultValue: "Carbs")) \(carbsPct)%").foregroundStyle(Color(hex: FoodPalette.label["carbs"]!))
                    Spacer()
                    Text("\(String(localized: "macros.fat", defaultValue: "Fat")) \(fatPct)%").foregroundStyle(Color(hex: FoodPalette.label["fat"]!))
                }
                .font(FATypography.sans(11, .semibold, relativeTo: .caption2)).padding(.top, 6)

                if let warning = NutritionMath.offsetWarning(offset: model.activeOffset, goal: model.goal, bodyFatPercent: model.bodyFatForGoal) {
                    let (fg, bg): (Color, Color) = switch warning.tone {
                    case .good: (Color(hex: 0x059669), Color(hex: 0xD1FAE5))
                    case .ok: (Color(hex: 0x0D9488), Color(hex: 0xF0FDFA))
                    case .caution: (Color(hex: 0xD97706), Color(hex: 0xFEF3C7))
                    }
                    Text(warning.message).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(fg).lineSpacing(4)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous)).padding(.top, 12)
                }
            }
        }
        .sheet(isPresented: $offsetOpen) {
            WheelPickerSheet(title: String(localized: "targets.offset.title", defaultValue: "Calorie Adjustment"), value: Double(model.activeOffset), range: -800...600, step: 50, format: { v in "\(v >= 0 ? "+" : "")\(Int(v)) kcal" }, onConfirm: { v in
                model.customOffset = Int(v); model.touch()
            })
        }
    }

    private func goalLabel(_ g: NutritionMath.Goal) -> String {
        switch g {
        case .build: String(localized: "goal.build", defaultValue: "Build")
        case .maintain: String(localized: "goal.maintain", defaultValue: "Maintain")
        case .cut: String(localized: "goal.cut", defaultValue: "Cut")
        }
    }
}

// MARK: - Macro targets

private struct MacroTargetsCard: View {
    @Bindable var model: NutritionTargetsModel
    @State private var expanded = false

    private var proteinPerKg: Double { model.weightValue > 0 ? (Double(model.displayMacros.proteinG) / model.weightValue * 10).rounded() / 10 : 1.8 }
    private var fatPercent: Int { model.displayGoalCalories > 0 ? Int((Double(model.displayMacros.fatG * 9) / Double(model.displayGoalCalories) * 100).rounded()) : 40 }
    private var fiberProgress: Double { max(0, min(1, model.consumedFiber / Double(max(1, model.fiberTarget)))) }

    private let proteinFill = Color(hex: FoodPalette.pastel["protein"]!), proteinLabel = Color(hex: FoodPalette.label["protein"]!)
    private let carbsFill = Color(hex: FoodPalette.pastel["carbs"]!), carbsLabel = Color(hex: FoodPalette.label["carbs"]!)
    private let fatFill = Color(hex: FoodPalette.pastel["fat"]!), fatLabel = Color(hex: FoodPalette.label["fat"]!)

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
                    HStack {
                        MicroLabel(text: String(localized: "targets.macros", defaultValue: "Macro Targets"), color: FAColor.forestSoft)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(ProfilePalette.muted).rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !expanded {
                    HStack(spacing: 0) {
                        column(String(localized: "macros.protein", defaultValue: "Protein"), grams: model.displayMacros.proteinG, sub: "\(proteinPerKg.formatted(.number.precision(.fractionLength(1)))) g/kg", color: proteinLabel)
                        Rectangle().fill(ProfilePalette.hairline).frame(width: 1)
                        column(String(localized: "macros.fat", defaultValue: "Fat"), grams: model.displayMacros.fatG, sub: "\(fatPercent)%", color: fatLabel)
                        Rectangle().fill(ProfilePalette.hairline).frame(width: 1)
                        column(String(localized: "macros.carbs", defaultValue: "Carbs"), grams: model.displayMacros.carbsG, sub: "±5g", color: carbsLabel)
                    }
                    .padding(.top, 14)
                } else {
                    VStack(spacing: 10) {
                        MacroSliderCard(title: String(localized: "macros.protein", defaultValue: "Protein"), grams: model.displayMacros.proteinG, secondary: "\(proteinPerKg.formatted(.number.precision(.fractionLength(1)))) g/kg", color: proteinLabel, context: NutritionMath.proteinContext(gPerKg: proteinPerKg)) {
                            SteppedSlider(value: proteinPerKg, range: 1.0...2.5, step: 0.1, fill: proteinFill, label: proteinLabel, format: { "\($0.formatted(.number.precision(.fractionLength(1)))) g/kg" }) { model.setProteinPerKg($0) }
                        }
                        MacroSliderCard(title: String(localized: "macros.fat", defaultValue: "Fat"), grams: model.displayMacros.fatG, secondary: "\(fatPercent)%", color: fatLabel, context: NutritionMath.fatContext(percent: fatPercent)) {
                            SteppedSlider(value: Double(fatPercent), range: 20...55, step: 1, fill: fatFill, label: fatLabel, optimal: 35...40, format: { "\(Int($0.rounded()))%" }) { model.setFatPercent($0) }
                        }
                        MacroSliderCard(title: String(localized: "macros.carbs", defaultValue: "Carbs"), grams: model.displayMacros.carbsG, secondary: "±5g", color: carbsLabel, context: NutritionMath.carbsContext(carbsG: model.displayMacros.carbsG, goalCalories: model.displayGoalCalories)) {
                            HStack(spacing: 16) {
                                roundStep("−") { model.nudgeCarbs(-5) }
                                Text("\(model.displayMacros.carbsG)g").font(FATypography.sans(16, .bold, relativeTo: .body)).foregroundStyle(carbsLabel).frame(minWidth: 60)
                                roundStep("+") { model.nudgeCarbs(5) }
                            }
                            .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 2)
                            VStack(spacing: 6) {
                                HStack {
                                    Text(String(localized: "targets.fiber", defaultValue: "Fiber")).font(FATypography.sans(11, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.ink)
                                    Spacer()
                                    Text("\(Int(model.consumedFiber.rounded()))g / \(model.fiberTarget)g").font(FATypography.sans(11, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.ink)
                                }
                                HashedBar(color: carbsFill, pct: fiberProgress, height: 7, raised: true)
                            }
                            .padding(.top, 10).overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }.padding(.top, 10)
                        }
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    private func column(_ title: String, grams: Int, sub: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased()).font(FATypography.sans(11, .semibold, relativeTo: .caption2)).tracking(0.4).foregroundStyle(color)
            Text("\(grams)g").font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(color)
            Text(sub).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func roundStep(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(FATypography.sans(20, .bold, relativeTo: .body)).foregroundStyle(Color(hex: FoodPalette.label["carbs"]!))
                .frame(width: 36, height: 36).background(ProfilePalette.accentSoft, in: Circle()).overlay { Circle().strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// The Expo `MacroSliderCard`: a soft inner panel with the title, grams, a secondary figure, the
/// control and a context line.
private struct MacroSliderCard<Control: View>: View {
    let title: String
    let grams: Int
    let secondary: String
    let color: Color
    let context: String
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(FATypography.sans(13, .bold, relativeTo: .caption)).foregroundStyle(color)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(grams)g").font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(color)
                    Text(secondary).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(color.opacity(0.6))
                }
            }
            control.padding(.top, 12)
            Text(context).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 10)
        }
        .padding(16)
        .background(ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
    }
}

/// The Expo `SteppedSlider`: a value readout, a tinted track with an optional optimal band, −/+ steps.
private struct SteppedSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let fill: Color
    let label: Color
    var optimal: ClosedRange<Double>? = nil
    let format: (Double) -> String
    let onChange: (Double) -> Void

    private var pct: Double { max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) }

    var body: some View {
        VStack(spacing: 10) {
            Text(format(value)).font(FATypography.display(18, relativeTo: .body)).foregroundStyle(label)
            HStack(spacing: 10) {
                stepButton("minus") { nudge(-1) }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(fill.opacity(0.18))
                        if let optimal {
                            let l = (optimal.lowerBound - range.lowerBound) / (range.upperBound - range.lowerBound)
                            let r = (optimal.upperBound - range.lowerBound) / (range.upperBound - range.lowerBound)
                            Capsule().fill(fill.opacity(0.35)).frame(width: geo.size.width * CGFloat(r - l)).offset(x: geo.size.width * CGFloat(l))
                        }
                        Capsule().fill(LinearGradient(colors: [fill.shaded(-0.2), fill], startPoint: .leading, endPoint: .trailing)).frame(width: max(12, geo.size.width * CGFloat(pct)))
                        Circle().fill(.white).frame(width: 18, height: 18).shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .overlay { Circle().strokeBorder(fill, lineWidth: 2) }
                            .offset(x: max(0, geo.size.width * CGFloat(pct) - 9))
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        let p = max(0, min(1, g.location.x / geo.size.width))
                        let raw = range.lowerBound + p * (range.upperBound - range.lowerBound)
                        let snapped = (raw / step).rounded() * step
                        let clamped = max(range.lowerBound, min(range.upperBound, snapped))
                        if abs(clamped - value) >= step / 2 { onChange(clamped) }
                    })
                }
                .frame(height: 18)
                stepButton("plus") { nudge(1) }
            }
            HStack {
                Text(format(range.lowerBound)); Spacer(); Text(format(range.upperBound))
            }
            .font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
        }
    }

    private func nudge(_ dir: Double) {
        let next = ((value + dir * step) * 100).rounded() / 100
        if range.contains(next) { onChange(next) }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(label)
                .frame(width: 30, height: 30).background(ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meals & snacks

private struct MealsSnacksCard: View {
    @Bindable var model: NutritionTargetsModel
    @State private var showPlan = false
    @State private var expandedSlot: String?

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel(text: String(localized: "targets.mealsSnacks", defaultValue: "Meals & Snacks"), color: FAColor.forestSoft).padding(.bottom, 14)
                HStack {
                    Spacer()
                    stepper(label: String(localized: "targets.meals", defaultValue: "meals"), value: model.mealsCount, min: 1, max: 6) { model.mealsPerDay = $0; model.touch() }
                    Spacer()
                    stepper(label: String(localized: "targets.snacks", defaultValue: "snacks"), value: model.snacksCount, min: 0, max: 4) { model.snacksPerDay = $0; model.touch() }
                    Spacer()
                }
                Button { withAnimation(.spring(duration: 0.3)) { showPlan.toggle() } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "targets.repartition", defaultValue: "Daily repartition")).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            Text(String(localized: "targets.repartition.sub", defaultValue: "How macros split across your day")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(ProfilePalette.muted).rotationEffect(.degrees(showPlan ? 180 : 0))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.top, 16)

                if showPlan {
                    VStack(spacing: 6) {
                        ForEach(NutritionMath.repartitionPlan(meals: model.mealsCount, snacks: model.snacksCount, targets: model.displayMacros)) { slot in
                            let open = expandedSlot == slot.id
                            Button { withAnimation(.spring(duration: 0.25)) { expandedSlot = open ? nil : slot.id } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(slot.title).font(FATypography.sans(13, .bold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                                        Spacer()
                                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(ProfilePalette.muted).rotationEffect(.degrees(open ? 180 : 0))
                                    }
                                    HStack(spacing: 6) {
                                        Text("\(slot.protein)g P").foregroundStyle(Color(hex: FoodPalette.label["protein"]!))
                                        Text("\(slot.carbs)g C").foregroundStyle(Color(hex: FoodPalette.label["carbs"]!))
                                        Text("\(slot.fat)g F").foregroundStyle(Color(hex: FoodPalette.label["fat"]!))
                                    }
                                    .font(FATypography.sans(12, .bold, relativeTo: .caption))
                                    if open {
                                        Text(slot.guidance).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(5).padding(.top, 2)
                                    }
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private func stepper(label: String, value: Int, min: Int, max: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            stepBtn("minus") { if value > min { onChange(value - 1) } }
            Text("\(value) \(label)").font(FATypography.sans(15, .bold, relativeTo: .body)).foregroundStyle(FAColor.ink).frame(minWidth: 70)
            stepBtn("plus") { if value < max { onChange(value + 1) } }
        }
    }

    private func stepBtn(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(ProfilePalette.muted)
                .frame(width: 30, height: 30).background(ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Understanding the 3 macros

private struct MacroInfoCard: View {
    let entry: MacroEducation.Entry
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onToggle) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.emoji) \(entry.title)").font(FATypography.sans(17, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                            Text(entry.tagline).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                        }
                        Spacer(minLength: 16)
                        Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(ProfilePalette.muted).rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    Text(entry.why).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(6).padding(.top, 14)
                    MicroLabel(text: String(localized: "targets.edu.sources", defaultValue: "Best sources")).padding(.top, 14).padding(.bottom, 8)
                    FlowLayout(spacing: 8) {
                        ForEach(entry.bestSources, id: \.self) { s in
                            Text(s).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(ProfilePalette.surfaceSoft, in: Capsule()).overlay { Capsule().strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
                        }
                    }
                    MicroLabel(text: String(localized: "targets.edu.timing", defaultValue: "Timing")).padding(.top, 14).padding(.bottom, 4)
                    Text(entry.timing).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(6)
                    MicroLabel(text: String(localized: "targets.edu.myths", defaultValue: "Common myths")).padding(.top, 14).padding(.bottom, 4)
                    ForEach(entry.myths, id: \.self) { m in
                        Text(m).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(6)
                    }
                }
            }
        }
    }
}
