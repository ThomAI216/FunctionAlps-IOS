import SwiftUI

/// Baseline & energy compass (the Expo `ob-baseline?edit=1` → `ob-activity` → `ob-energy` in edit mode):
/// three steps on one stack — body values, activity, the recalculated compass — then back to the profile.
/// One write, on the activity step, once all five inputs are known (never half a baseline on the row).
struct BaselineEditView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    private enum Step { case body, activity, energy }
    @State private var step: Step = .body
    @State private var member: Member?
    @State private var sex: MemberProfile.Sex?
    @State private var age = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var activity: ActivityLevel?
    @State private var touched: Set<String> = []
    @State private var saving = false
    @State private var saveError: String?
    @State private var savedKcal: Int?
    @FocusState private var focus: String?

    private var bodyOk: Bool {
        sex != nil && !age.isEmpty && !height.isEmpty && !weight.isEmpty
            && BaselineLogic.ageError(age) == nil && BaselineLogic.heightError(height) == nil && BaselineLogic.weightError(weight) == nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Button {
                        switch step {
                        case .body: dismiss()
                        case .activity: withAnimation { step = .body }
                        case .energy: withAnimation { step = .activity }
                        }
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium)).foregroundStyle(FAColor.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
                    Text(step == .energy ? String(localized: "baseline.energy.eyebrow", defaultValue: "Your energy needs") : String(localized: "profile.details", defaultValue: "Your baseline"))
                        .font(FATypography.sans(12, .semibold, relativeTo: .caption)).tracking(1.2).textCase(.uppercase).foregroundStyle(FAColor.forestSoft)
                }
                .padding(.vertical, 12)

                switch step {
                case .body: bodyStep
                case .activity: activityStep
                case .energy: energyStep
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard member == nil, let m = try? await dependencies.members.currentMember() else { return }
            member = m
            // Known values pre-filled — nobody is asked to re-type what FunctionAlps already has.
            sex = m.profile?.sex
            age = m.profile?.age.map { "\($0)" } ?? ""
            height = m.profile?.heightCm.map { formatNumber($0) } ?? ""
            weight = m.profile?.weightKg.map { formatNumber($0) } ?? ""
            activity = m.profile?.activityLevel.flatMap(ActivityLevel.init(rawValue:))
        }
    }

    private func formatNumber(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v) }

    // MARK: Step 1 · body

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "baseline.edit.title", defaultValue: "Update your baseline.")).font(FATypography.display(28, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).padding(.bottom, 12)
            Text(String(localized: "baseline.intro1", defaultValue: "We’ll start with a few basic measurements to estimate how much energy your body typically needs each day."))
                .font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(7).padding(.bottom, 8)
            Text(String(localized: "baseline.intro2", defaultValue: "This gives us useful context when looking at your meals."))
                .font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(7).padding(.bottom, 22)

            field(String(localized: "baseline.age", defaultValue: "How old are you?"), error: touched.contains("age") ? BaselineLogic.ageError(age) : nil) {
                numberInput($age, id: "age", placeholder: "e.g. 42", suffix: String(localized: "baseline.years", defaultValue: "years"), decimal: false)
            }
            field(String(localized: "baseline.sex", defaultValue: "Biological sex"), helper: String(localized: "baseline.sex.helper", defaultValue: "Used to estimate your energy requirements.")) {
                HStack(spacing: 10) {
                    chip(String(localized: "baseline.female", defaultValue: "Female"), selected: sex == .female) { sex = .female }
                    chip(String(localized: "baseline.male", defaultValue: "Male"), selected: sex == .male) { sex = .male }
                }
            }
            field(String(localized: "profile.height", defaultValue: "Height"), error: touched.contains("height") ? BaselineLogic.heightError(height) : nil) {
                numberInput($height, id: "height", placeholder: "e.g. 172", suffix: "cm", decimal: true)
            }
            field(String(localized: "baseline.weight", defaultValue: "Current weight"), error: touched.contains("weight") ? BaselineLogic.weightError(weight) : nil) {
                numberInput($weight, id: "weight", placeholder: "e.g. 68", suffix: "kg", decimal: true)
            }

            ForestPillButton(title: String(localized: "action.continue", defaultValue: "Continue"), enabled: bodyOk) {
                focus = nil
                withAnimation { step = .activity }
            }
            .padding(.top, 10)
            Text(String(localized: "baseline.later", defaultValue: "You can update any of this later in your profile."))
                .font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).frame(maxWidth: .infinity).padding(.top, 12)
        }
    }

    private func field<Content: View>(_ label: String, helper: String? = nil, error: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
            if let helper { Text(helper).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted) }
            content()
            if let error { Text(error).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red) }
        }
        .padding(.bottom, 18)
    }

    private func numberInput(_ text: Binding<String>, id: String, placeholder: String, suffix: String, decimal: Bool) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .focused($focus, equals: id)
                .onChange(of: focus) { _, now in if now != id, !text.wrappedValue.isEmpty { touched.insert(id) } }
                .font(FATypography.sans(17, relativeTo: .body)).foregroundStyle(FAColor.ink)
            Text(suffix).font(FATypography.sans(13, .semibold, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focus == id ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: 1.5) }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(selected ? FAColor.charcoal : FAColor.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(selected ? FAColor.forestSoft : ProfilePalette.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(selected ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Step 2 · activity (the one write)

    private var activityStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "baseline.activity.edit", defaultValue: "Update your activity.")).font(FATypography.display(28, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).padding(.bottom, 12)
            Text(String(localized: "baseline.activity.intro", defaultValue: "This is the last piece of the estimate. Don’t overthink it · an ordinary week is the right answer, not your best one."))
                .font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(7).padding(.bottom, 22)
            VStack(spacing: 9) {
                ForEach(Array(ActivityLevel.allCases.enumerated()), id: \.element.id) { i, level in
                    ActivityCard(index: i, level: level, selected: activity == level) { activity = level }
                }
            }
            ForestPillButton(title: saving ? String(localized: "baseline.saving", defaultValue: "Saving…") : String(localized: "action.save", defaultValue: "Save"), enabled: activity != nil, busy: saving) {
                Task { await save() }
            }
            .padding(.top, 22)
            if let saveError {
                Text(saveError).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4).padding(.top, 12)
            } else {
                Text(String(localized: "baseline.activity.footnote", defaultValue: "Pick the one that sounds most like a normal week."))
                    .font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).frame(maxWidth: .infinity).padding(.top, 12)
            }
        }
    }

    private func save() async {
        guard !saving, let member, let values = BaselineLogic.resolve(sex: sex, age: age, height: height, weight: weight, activity: activity) else { return }
        saving = true
        saveError = nil
        do {
            let profile = try await dependencies.profile.saveBaseline(patientId: member.patientId, values: values)
            // The DB trigger is the authority; the identical local formula stands in until it answers.
            savedKcal = profile?.tdeeKcal.map(BaselineLogic.roundToNearest50) ?? BaselineLogic.estimateKcal(values)
            withAnimation { step = .energy }
        } catch {
            saveError = String(localized: "baseline.saveFailed", defaultValue: "We couldn't save that just now. Your answers are safe · try again.")
        }
        saving = false
    }

    // MARK: Step 3 · the compass

    private var energyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "baseline.energy.title", defaultValue: "Your estimated daily energy target")).font(FATypography.display(28, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).lineSpacing(4).padding(.bottom, 18)
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "safari").font(.system(size: 15, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                        Text(String(localized: "baseline.energy.compass", defaultValue: "Your energy compass").uppercased()).font(FATypography.sans(12, .semibold, relativeTo: .caption)).tracking(1.2).foregroundStyle(FAColor.forestSoft)
                    }
                    (Text("~\(savedKcal.map { $0.formatted() } ?? "·")").font(FATypography.display(38, relativeTo: .largeTitle)).foregroundColor(FAColor.ink)
                        + Text("  " + String(localized: "baseline.energy.unit", defaultValue: "kcal / day")).font(FATypography.sans(16, relativeTo: .body)).foregroundColor(ProfilePalette.muted))
                        .accessibilityLabel(String(localized: "baseline.energy.a11y", defaultValue: "About \(savedKcal ?? 0) kilocalories per day"))
                    Text(String(localized: "baseline.energy.sub", defaultValue: "An estimate of your typical daily energy needs.")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                }
            }
            .padding(.bottom, 18)
            Text(String(localized: "baseline.energy.p1", defaultValue: "Based on your profile and activity level, this is our current estimate of how much energy your body uses in a typical day."))
                .font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(ProfilePalette.muted).lineSpacing(7).padding(.bottom, 10)
            (Text(String(localized: "baseline.energy.p2a", defaultValue: "Think of it as a ")).foregroundColor(ProfilePalette.muted)
                + Text(String(localized: "baseline.energy.p2b", defaultValue: "compass, not a score.")).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundColor(FAColor.ink)
                + Text(" " + String(localized: "baseline.energy.p2c", defaultValue: "You don’t need to hit this number perfectly every day.")).foregroundColor(ProfilePalette.muted))
                .font(FATypography.sans(15, relativeTo: .body)).lineSpacing(7).padding(.bottom, 20)
            FACard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "baseline.energy.made", defaultValue: "We’re much more interested in what those calories are made of · and how you respond to them."))
                        .font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(6)
                    FlowLayout(spacing: 7) {
                        nutrientChip(String(localized: "macros.proteins", defaultValue: "Proteins"), FAColor.protein)
                        nutrientChip(String(localized: "macros.fats", defaultValue: "Fats"), FAColor.fat)
                        nutrientChip(String(localized: "macros.carbohydrates", defaultValue: "Carbohydrates"), FAColor.carbs)
                        nutrientChip(String(localized: "macros.fibres", defaultValue: "Fibres"), FAColor.kcal)
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
            ForestPillButton(title: String(localized: "action.done", defaultValue: "Done")) { dismiss() }.padding(.top, 22)
        }
    }

    private func nutrientChip(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(FATypography.sans(12.5, .medium, relativeTo: .caption)).foregroundStyle(FAColor.ink)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(ProfilePalette.surfaceSoft, in: Capsule())
        .overlay { Capsule().strokeBorder(ProfilePalette.hairline, lineWidth: 1) }
    }
}

/// The activity cards rise in one after another (55 ms apart) and give a little when selected.
struct ActivityCard: View {
    let index: Int
    let level: ActivityLevel
    let selected: Bool
    let action: () -> Void
    @State private var entered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(level.title).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(FAColor.forestSoft) }
                }
                Text(level.body).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color(hex: 0x4A8A5C, opacity: 0.13) : ProfilePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? FAColor.forestSoft : ProfilePalette.hairline, lineWidth: selected ? 2 : 1) }
            .scaleEffect(selected ? 1.015 : 1)
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 14)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        .onAppear {
            withAnimation(.easeOut(duration: 0.26).delay(Double(index) * 0.055)) { entered = true }
        }
    }
}
