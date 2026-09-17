import SwiftUI

/// "How did that meal feel?" — 2.5 h after a meal, or any time from the meal page. THREE reads —
/// energy, focus, digestion — and, when one of them went badly, one row of pills asking what exactly.
/// One `nb_meal_reactions` row per answer; the row IS the "they answered" signal.
struct MealReactionSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let mealId: String
    let mealName: String?
    let onSaved: (MealReaction) -> Void

    @State private var feedback = MealFeedback()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "reaction.title", defaultValue: "How did that meal feel?"))
                        .font(FATypography.title).foregroundStyle(FAColor.ink)
                    if let mealName, !mealName.isEmpty {
                        Text(mealName).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary).lineLimit(1)
                    }
                    Text(String(localized: "reaction.intro", defaultValue: "Three taps, two hours later — that is what teaches which meals sit well with you. Skip anything you don't know."))
                        .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).lineSpacing(4).padding(.top, 2)
                }

                readCard(title: String(localized: "reaction.energy", defaultValue: "Your energy"),
                         words: MealFeedbackCopy.energyWords(), accent: Color(hex: 0xD97706),
                         read: $feedback.energy,
                         pillTitle: String(localized: "reaction.energy.what", defaultValue: "What did it feel like?"),
                         pills: MealFeedbackCopy.energyPills, selected: $feedback.energyPills)

                readCard(title: String(localized: "reaction.focus", defaultValue: "Your focus"),
                         words: MealFeedbackCopy.focusWords(), accent: Color(hex: 0x6366F1),
                         read: $feedback.focus,
                         pillTitle: String(localized: "reaction.focus.what", defaultValue: "What did it feel like?"),
                         pills: MealFeedbackCopy.focusPills, selected: $feedback.focusPills)

                readCard(title: String(localized: "reaction.digestion", defaultValue: "Your digestion"),
                         words: MealFeedbackCopy.digestionWords(), accent: Color(hex: 0x14B8A6),
                         read: $feedback.digestion,
                         pillTitle: String(localized: "reaction.digestion.what", defaultValue: "What felt off?"),
                         pills: MealFeedbackCopy.digestionPills, selected: $feedback.digestionPills)

                if let error {
                    Text(error).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4)
                }

                FAButton(title: saving ? String(localized: "action.saving", defaultValue: "Saving…") : String(localized: "reaction.save", defaultValue: "Save"), isLoading: saving, isEnabled: feedback.hasAnswer) {
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

    /// One read: five words, and the "what exactly" row underneath once the read is a poor one.
    private func readCard(title: String, words: [String], accent: Color, read: Binding<MealFeedback.Read?>,
                          pillTitle: String, pills: [PillOption], selected: Binding<[String]>) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(FATypography.headline).foregroundStyle(FAColor.ink)
                ReadStepRow(words: words, accent: accent, value: read)
                if read.wrappedValue?.isPoor == true {
                    Divider().overlay(FAColor.separator).padding(.top, 2)
                    PillGroupView(title: pillTitle, options: pills,
                                  isOn: { selected.wrappedValue.contains($0) },
                                  onToggle: { key in
                                      var current = selected.wrappedValue
                                      if let i = current.firstIndex(of: key) { current.remove(at: i) } else { current.append(key) }
                                      selected.wrappedValue = current
                                  },
                                  accent: accent)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: read.wrappedValue)
        }
    }

    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            let member = try await dependencies.members.currentMember()
            try await dependencies.meals.saveReaction(
                mealId: mealId, patientId: member.patientId, overall: feedback.overall,
                bloating: feedback.bloating, fullness: feedback.fullness, gas: feedback.gasBurden,
                burning: feedback.burning, fatigue: feedback.fatigue,
                digestion: feedback.digestion?.rawValue, energy: feedback.energy?.rawValue,
                flags: feedback.flags, responses: feedback.responses
            )
            dependencies.notifications.mealRated(id: mealId)
            onSaved(MealReaction(overall: feedback.overall, flags: feedback.flags,
                                 bloating: Double(feedback.bloating), fullness: Double(feedback.fullness), gas: Double(feedback.gasBurden)))
            dismiss()
        } catch let e as AppError {
            error = e.userMessage
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// Five words, one tappable at a time — tapping the active one clears it, so "I'd rather not say"
/// stays one tap away.
private struct ReadStepRow: View {
    let words: [String]
    let accent: Color
    @Binding var value: MealFeedback.Read?

    private func label(for step: MealFeedback.Read) -> String {
        guard let i = MealFeedback.Read.allCases.firstIndex(of: step), words.indices.contains(i) else { return "" }
        return words[i]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MealFeedback.Read.allCases) { step in
                let on = value == step
                let word = label(for: step)
                Button { value = on ? nil : step } label: {
                    Text(word)
                        .font(FATypography.sans(11.5, .semibold, relativeTo: .caption))
                        .foregroundStyle(on ? Color.white : FAColor.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(on ? accent : Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ProfilePalette.hairline, lineWidth: on ? 0 : 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(word)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
