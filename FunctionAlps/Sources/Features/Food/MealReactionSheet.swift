import SwiftUI

/// "How did that meal feel?" — the Expo `MealReactionModal`, 2.5 h after a meal (or any time from the
/// meal page). Overall 0–10 + three gut symptoms; one `nb_meal_reactions` row per answer. A row exists
/// only when something was rated — the row IS the "they answered" signal.
struct MealReactionSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let mealId: String
    let mealName: String?
    let onSaved: (MealReaction) -> Void

    @State private var overall: Int?
    @State private var bloating = 0
    @State private var fullness = 0
    @State private var gas = 0
    @State private var saving = false
    @State private var error: String?

    private var hasAnswer: Bool { overall != nil || bloating > 0 || fullness > 0 || gas > 0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "reaction.title", defaultValue: "How did that meal feel?"))
                        .font(FATypography.title).foregroundStyle(FAColor.ink)
                    if let mealName, !mealName.isEmpty {
                        Text(mealName).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary).lineLimit(1)
                    }
                    Text(String(localized: "reaction.intro", defaultValue: "Ten seconds now teaches which meals sit well with you. Skip anything you don't know."))
                        .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).lineSpacing(4).padding(.top, 2)
                }

                FACard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "reaction.overall", defaultValue: "Overall, 2–3 hours later")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                        HStack(spacing: 5) {
                            ForEach(0...10, id: \.self) { n in
                                let on = overall == n
                                Button { overall = on ? nil : n } label: {
                                    Text("\(n)")
                                        .font(FATypography.sans(12, .semibold, relativeTo: .caption))
                                        .foregroundStyle(on ? Color.white : FAColor.ink)
                                        .frame(maxWidth: .infinity).frame(height: 34)
                                        .background(on ? tone(for: n) : Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: on ? 0 : 1) }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(n)")
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        HStack {
                            Text(String(localized: "reaction.scale.low", defaultValue: "Rough")).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(ProfilePalette.red)
                            Spacer()
                            Text(String(localized: "reaction.scale.high", defaultValue: "Sat well")).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(Color(hex: 0x4A8A5C))
                        }
                    }
                }

                FACard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "reaction.gut", defaultValue: "Your gut")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                        SymptomRow(label: String(localized: "reaction.bloating", defaultValue: "Bloating"), value: $bloating)
                        SymptomRow(label: String(localized: "reaction.fullness", defaultValue: "Heaviness / fullness"), value: $fullness)
                        SymptomRow(label: String(localized: "reaction.gas", defaultValue: "Gas"), value: $gas)
                    }
                }

                if let error {
                    Text(error).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4)
                }

                FAButton(title: saving ? String(localized: "action.saving", defaultValue: "Saving…") : String(localized: "reaction.save", defaultValue: "Save"), isLoading: saving, isEnabled: hasAnswer) {
                    Task { await save() }
                }
                Button(String(localized: "reaction.skip", defaultValue: "Not now")) { dismiss() }
                    .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.top, 22)
            .padding(.bottom, FASpacing.lg)
        }
        .background(FAColor.background)
    }

    private func tone(for n: Int) -> Color {
        n >= 7 ? Color(hex: 0x4A8A5C) : n >= 4 ? Color(hex: 0xC99A3B) : Color(hex: 0xC0453A)
    }

    /// The flag vocabulary the Food tab lines and the food×reaction engine already read.
    static func flags(overall: Int?, bloating: Int, fullness: Int, gas: Int) -> [String] {
        var out: [String] = []
        if let overall { if overall < 4 { out.append("overall_rough") } else if overall < 7 { out.append("overall_off") } }
        if bloating >= 6 { out.append("bloating") }
        if fullness >= 6 { out.append("heavy") }
        if gas >= 6 { out.append("gas") }
        return out
    }

    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            let member = try await dependencies.members.currentMember()
            let flags = Self.flags(overall: overall, bloating: bloating, fullness: fullness, gas: gas)
            var responses: [String: Double] = ["bloating": Double(bloating), "fullness": Double(fullness), "gas": Double(gas)]
            if let overall { responses["overall"] = Double(overall) }
            try await dependencies.meals.saveReaction(mealId: mealId, patientId: member.patientId, overall: overall.map(Double.init), bloating: bloating, fullness: fullness, gas: gas, flags: flags, responses: responses)
            dependencies.notifications.mealRated(id: mealId)
            onSaved(MealReaction(overall: overall.map(Double.init), flags: flags))
            dismiss()
        } catch let e as AppError {
            error = e.userMessage
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// None · Mild · Moderate · Strong → 0 · 3 · 6 · 9 (the 0–10 columns the engine aggregates).
private struct SymptomRow: View {
    let label: String
    @Binding var value: Int
    private struct Step: Identifiable { let id: Int; let label: String }
    private let steps: [Step] = [
        Step(id: 0, label: String(localized: "reaction.level.none", defaultValue: "None")),
        Step(id: 3, label: String(localized: "reaction.level.mild", defaultValue: "Mild")),
        Step(id: 6, label: String(localized: "reaction.level.moderate", defaultValue: "Moderate")),
        Step(id: 9, label: String(localized: "reaction.level.strong", defaultValue: "Strong")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
            HStack(spacing: 6) {
                ForEach(steps) { step in
                    let on = value == step.id
                    Button { value = step.id } label: {
                        Text(step.label)
                            .font(FATypography.sans(12, .semibold, relativeTo: .caption))
                            .foregroundStyle(on ? Color.white : FAColor.ink)
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background(on ? FAColor.brand : Color.white.opacity(0.55), in: Capsule())
                            .overlay { Capsule().strokeBorder(ProfilePalette.hairline, lineWidth: on ? 0 : 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
