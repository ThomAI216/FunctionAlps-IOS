import SwiftUI

/// Closing the day — D01–D06, about thirty seconds, done in the evening.
///
/// **This is the screen the whole pillar rests on.** See §2.6 of
/// `docs/NUTRITION_TRACK_IMPLEMENTATION.md`. A missed morning of the sleep diary
/// is visibly missing; a missed lunch is not, and every error it causes points
/// the same way. The member's own answer to D01 is what per-day counts are gated
/// on, so this screen's job is to make giving it feel like nothing.
///
/// Four things it must keep:
///  1. Answering "no" costs nothing. No warning colour, no exclamation, no streak
///     — there is no streak in this feature.
///  2. The consequence is stated the moment it applies, plainly, once.
///  3. The day's logged meals appear ABOVE the question, so it is answerable
///     without scrolling back through the feed.
///  4. Only D01 is required. A close that demanded six answers would not be a
///     thirty-second close.
///
/// `FAColor.scale` — the five-level functional ramp — is deliberately absent. One
/// accent for a selected value, neutral for the rest.
struct DayCloseView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var close: NutritionDayClose
    /// What we already have for today, so D01 is answerable in place.
    let loggedToday: [LoggedEventSummary]
    let dayNumber: Int
    let totalDays: Int
    let optIns: NutritionSignalOptIns
    var onSave: (NutritionDayClose) -> Void = { _ in }

    init(
        close: NutritionDayClose,
        loggedToday: [LoggedEventSummary] = [],
        dayNumber: Int,
        totalDays: Int,
        optIns: NutritionSignalOptIns = [],
        onSave: @escaping (NutritionDayClose) -> Void = { _ in }
    ) {
        _close = State(initialValue: close)
        self.loggedToday = loggedToday
        self.dayNumber = dayNumber
        self.totalDays = totalDays
        self.optIns = optIns
        self.onSave = onSave
    }

    private let accent = FAColor.forestSoft

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                header
                whatWeHaveCard
                completenessCard
                dayShapeCard
                if optIns.contains(.digestion) || optIns.contains(.stool) { comfortCard }
                fluidCard
                noteCard
                footnote
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                String(
                    localized: "nutrition.close.eyebrow",
                    defaultValue: "Day \(dayNumber) of \(totalDays) · about thirty seconds"
                )
            )
            .font(FATypography.sans(11, relativeTo: .caption2))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(FAColor.inkSecondary)

            Text(String(localized: "nutrition.close.title", defaultValue: "Closing today"))
                .font(FATypography.title)
                .foregroundStyle(FAColor.ink)

            Text(
                String(
                    localized: "nutrition.close.intro",
                    defaultValue: "You don’t need to add anything you forgot. We just need to know whether there was anything."
                )
            )
            .font(FATypography.sans(13, relativeTo: .subheadline))
            .foregroundStyle(FAColor.inkSecondary)
            .lineSpacing(4)
            .padding(.top, 2)
        }
        .padding(.top, FASpacing.sm)
    }

    // MARK: what we have — so D01 is answerable in place

    private var whatWeHaveCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "nutrition.close.have", defaultValue: "What we have for today"))
                    .font(FATypography.sans(11, relativeTo: .caption2))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(FAColor.inkSecondary)

                if loggedToday.isEmpty {
                    Text(
                        String(
                            localized: "nutrition.close.haveNone",
                            defaultValue: "Nothing logged today. If you genuinely didn’t eat much, say so below — that is useful and we would rather know."
                        )
                    )
                    .font(FATypography.sans(12.5, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
                    .lineSpacing(4)
                } else {
                    ForEach(loggedToday) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(e.at)
                                // FATypography has no mono face; the system one keeps the
                                // time column aligned, which is the only reason it is here.
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(FAColor.inkSecondary)
                                .frame(width: 42, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.title)
                                    .font(FATypography.sans(13, relativeTo: .subheadline))
                                    .foregroundStyle(FAColor.ink)
                                // The provenance line. An unconfirmed model guess must
                                // never read like something a person agreed with.
                                Text(e.provenance)
                                    .font(FATypography.sans(11, relativeTo: .caption2))
                                    .foregroundStyle(FAColor.inkSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: D01 — the field this screen exists for

    private var completenessCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                FieldHeading(
                    id: "D01",
                    title: String(
                        localized: "nutrition.close.d01",
                        defaultValue: "Is that everything you ate and drank today?"
                    ),
                    hint: String(
                        localized: "nutrition.close.d01.hint",
                        defaultValue: "If you missed something, that’s completely fine — just tell us, and we’ll leave today out of the counts rather than quietly assuming you ate less."
                    )
                )

                VStack(spacing: 6) {
                    ForEach(DayCompleteness.allCases) { option in
                        completenessButton(option)
                    }
                }

                // Stated the moment it applies. Once, plainly, and never as a
                // reprimand — a member who feels watched stops logging, and then
                // there is nothing at all.
                if let c = close.completeness, !c.countsTowardRates {
                    consequenceNote
                } else if close.completeness == .complete {
                    thanksNote
                }
            }
        }
    }

    private func completenessButton(_ option: DayCompleteness) -> some View {
        let on = close.completeness == option
        return Button {
            close.completeness = option
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol(for: option))
                    .font(.system(size: 14, weight: .medium))
                Text(label(for: option))
                    .font(FATypography.sans(14, relativeTo: .body))
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? FAColor.cream : FAColor.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? accent : FAColor.surfaceMuted)
            )
        }
        .buttonStyle(.plain)
    }

    private func symbol(for option: DayCompleteness) -> String {
        switch option {
        case .complete: return "checkmark"
        case .incomplete: return "fork.knife"
        case .notSure: return "questionmark.circle"
        }
    }

    private func label(for option: DayCompleteness) -> String {
        switch option {
        case .complete:
            return String(localized: "nutrition.close.d01.yes", defaultValue: "Yes, that’s everything")
        case .incomplete:
            return String(localized: "nutrition.close.d01.no", defaultValue: "No, I missed some")
        case .notSure:
            return String(localized: "nutrition.close.d01.unsure", defaultValue: "I’m not sure")
        }
    }

    private var consequenceNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                String(
                    localized: "nutrition.close.consequence",
                    defaultValue: "Understood — today won’t count toward “how many times a day”, your eating window, or how much you drank. What you did log still counts for everything else: what was in each meal, how hungry you were, how you felt after."
                )
            )
            .font(FATypography.sans(12.5, relativeTo: .caption))
            .foregroundStyle(FAColor.inkSecondary)
            .lineSpacing(4)

            Text(
                String(
                    localized: "nutrition.close.noStreak",
                    defaultValue: "Nothing here is a streak and there is nothing to break. Days like this are normal and the week still works with a few of them."
                )
            )
            .font(FATypography.sans(11.5, relativeTo: .caption2))
            .foregroundStyle(FAColor.inkSecondary)
            .lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FAColor.surfaceMuted)
        )
    }

    private var thanksNote: some View {
        Text(
            String(
                localized: "nutrition.close.thanks",
                defaultValue: "Thank you — that’s what lets us say anything about how often and when you eat."
            )
        )
        .font(FATypography.sans(12.5, relativeTo: .caption))
        .foregroundStyle(accent)
        .lineSpacing(4)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.opacity(0.10))
        )
    }

    // MARK: D02 / D03

    private var dayShapeCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    FieldHeading(
                        id: "D02",
                        title: String(localized: "nutrition.close.d02", defaultValue: "What kind of day was today?"),
                        hint: String(
                            localized: "nutrition.close.d02.hint",
                            defaultValue: "Eating differs between a Tuesday and a Saturday as much as sleep does, so we compare the two rather than blending them."
                        )
                    )
                    HStack(spacing: 6) {
                        ForEach(NutritionDayType.allCases) { t in
                            ChipButton(
                                title: t == .obligation
                                    ? String(localized: "nutrition.day.obligation", defaultValue: "Work or obligation")
                                    : String(localized: "nutrition.day.free", defaultValue: "A free day"),
                                isOn: close.dayType == t,
                                accent: accent
                            ) { close.dayType = t }
                        }
                        Spacer(minLength: 0)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    FieldHeading(
                        id: "D03",
                        title: String(localized: "nutrition.close.d03", defaultValue: "Anything unusual?"),
                        hint: String(
                            localized: "nutrition.close.d03.hint",
                            defaultValue: "Context, not excuses. A week with a birthday dinner in it is a normal week."
                        )
                    )
                    FlowChips(
                        options: NutritionDayModifier.allCases,
                        isOn: { close.modifiers.contains($0) },
                        title: { modifierLabel($0) },
                        accent: accent
                    ) { m in
                        if close.modifiers.contains(m) { close.modifiers.remove(m) }
                        else { close.modifiers.insert(m) }
                    }
                }
            }
        }
    }

    private func modifierLabel(_ m: NutritionDayModifier) -> String {
        switch m {
        case .travel: return String(localized: "nutrition.mod.travel", defaultValue: "Travelled")
        case .illness: return String(localized: "nutrition.mod.unwell", defaultValue: "Unwell")
        case .eatingOut: return String(localized: "nutrition.mod.out", defaultValue: "Ate out")
        case .socialEvent: return String(localized: "nutrition.mod.social", defaultValue: "Social event")
        case .trainingHard: return String(localized: "nutrition.mod.training", defaultValue: "Trained hard")
        case .menstrual: return String(localized: "nutrition.mod.period", defaultValue: "Period")
        }
    }

    // MARK: D04

    private var comfortCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 9) {
                FieldHeading(
                    id: "D04",
                    title: String(localized: "nutrition.close.d04", defaultValue: "How was your digestion today?"),
                    hint: String(localized: "nutrition.close.d04.hint", defaultValue: "Your whole day, not any one meal.")
                )
                ZeroToTen(value: $close.digestiveComfort, accent: accent)
                HStack {
                    Text(String(localized: "nutrition.close.d04.low", defaultValue: "0 — very uncomfortable"))
                    Spacer()
                    Text(String(localized: "nutrition.close.d04.high", defaultValue: "10 — no trouble at all"))
                }
                .font(FATypography.sans(11, relativeTo: .caption2))
                .foregroundStyle(FAColor.inkSecondary)
            }
        }
    }

    // MARK: D05

    private var fluidCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 9) {
                FieldHeading(
                    id: "D05",
                    title: String(localized: "nutrition.close.d05", defaultValue: "Roughly how much plain fluid?"),
                    hint: String(
                        localized: "nutrition.close.d05.hint",
                        defaultValue: "Water, tea, anything unsweetened. A rough band is honest; a number to the decilitre would not be."
                    )
                )
                FlowChips(
                    options: FluidBand.allCases,
                    isOn: { close.fluid == $0 },
                    title: { fluidLabel($0) },
                    accent: accent
                ) { close.fluid = (close.fluid == $0) ? nil : $0 }
            }
        }
    }

    private func fluidLabel(_ b: FluidBand) -> String {
        switch b {
        case .under075: return String(localized: "nutrition.fluid.1", defaultValue: "Under 0.75 L")
        case .b075to125: return String(localized: "nutrition.fluid.2", defaultValue: "0.75–1.25 L")
        case .b125to175: return String(localized: "nutrition.fluid.3", defaultValue: "1.25–1.75 L")
        case .b175to25: return String(localized: "nutrition.fluid.4", defaultValue: "1.75–2.5 L")
        case .over25: return String(localized: "nutrition.fluid.5", defaultValue: "Over 2.5 L")
        }
    }

    // MARK: D06

    private var noteCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 9) {
                FieldHeading(
                    id: "D06",
                    title: String(localized: "nutrition.close.d06", defaultValue: "Anything you want to note?"),
                    hint: String(
                        localized: "nutrition.close.d06.hint",
                        defaultValue: "Optional, always. Nobody’s algorithm reads this — a person does."
                    )
                )
                TextEditor(text: Binding(get: { close.note ?? "" }, set: { close.note = $0.isEmpty ? nil : $0 }))
                    .font(FATypography.sans(14, relativeTo: .body))
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FAColor.surfaceMuted)
                    )

                if let n = close.note, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(
                        String(
                            localized: "nutrition.close.d06.read",
                            defaultValue: "Your practitioner reads anything written here before your results are released. That is a person’s job, deliberately — the rules that flag things for review only read the buttons above, so this is how something you write actually reaches someone."
                        )
                    )
                    .font(FATypography.sans(11.5, relativeTo: .caption2))
                    .foregroundStyle(FAColor.inkSecondary)
                    .lineSpacing(3)
                }
            }
        }
    }

    // MARK: footnote + save

    private var footnote: some View {
        Text(
            String(
                localized: "nutrition.close.why",
                defaultValue: "Why we ask at all: a missed night of sleep is obviously missing — the entry isn’t there. A missed lunch isn’t, so it looks like a day you simply ate less. One tap is what keeps that from happening."
            )
        )
        .font(FATypography.sans(11.5, relativeTo: .caption2))
        .foregroundStyle(FAColor.inkSecondary)
        .lineSpacing(3)
        .padding(.top, 2)
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            Button {
                var saved = close
                saved.completedAt = Date()
                onSave(saved)
                dismiss()
            } label: {
                Text(String(localized: "nutrition.close.save", defaultValue: "Close the day"))
                    .font(FATypography.sans(15, .medium, relativeTo: .body))
                    .foregroundStyle(FAColor.cream)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(close.canSubmit ? accent : FAColor.inkSecondary.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!close.canSubmit)

            Text(
                close.canSubmit
                    ? String(localized: "nutrition.close.done", defaultValue: "That’s it — see you tomorrow.")
                    : String(localized: "nutrition.close.prompt", defaultValue: "Answer the first question and you’re done.")
            )
            .font(FATypography.sans(12, relativeTo: .caption))
            .foregroundStyle(FAColor.inkSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, FASpacing.md)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Small shared pieces

/// One logged event, as the close screen lists it. Deliberately minimal: this is a
/// reminder, not a second meal feed, and it carries no score.
struct LoggedEventSummary: Sendable, Identifiable, Equatable {
    let id: String
    /// "HH:mm"
    let at: String
    let title: String
    /// Which provenance layer named the contents. An unconfirmed model guess must
    /// never read like something a person agreed with.
    let provenance: String
}

private struct FieldHeading: View {
    let id: String
    let title: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(id)
                    .font(.system(size: 10, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(FAColor.inkSecondary)
                Text(title)
                    .font(FATypography.headline)
                    .foregroundStyle(FAColor.ink)
            }
            if let hint {
                Text(hint)
                    .font(FATypography.sans(12, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
                    .lineSpacing(3)
            }
        }
    }
}

private struct ChipButton: View {
    let title: String
    let isOn: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FATypography.sans(12.5, relativeTo: .caption))
                .foregroundStyle(isOn ? FAColor.cream : FAColor.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn ? accent : FAColor.surfaceMuted))
        }
        .buttonStyle(.plain)
    }
}

private struct FlowChips<T: Identifiable & Hashable>: View {
    let options: [T]
    let isOn: (T) -> Bool
    let title: (T) -> String
    let accent: Color
    let onTap: (T) -> Void

    var body: some View {
        // `.flexible` rather than a fixed grid: the labels vary in length and a
        // fixed column count would leave ragged gaps on a narrow phone.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(options) { o in
                ChipButton(title: title(o), isOn: isOn(o), accent: accent) { onTap(o) }
            }
        }
    }
}

/// 0–10, one accent for the selected value and neutral for the rest.
/// **Never `FAColor.scale`** — a ramp repeated down a page lets a member assemble
/// by eye exactly the score this pillar refuses to give.
private struct ZeroToTen: View {
    @Binding var value: Int?
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0...10, id: \.self) { n in
                let on = value == n
                Button {
                    value = on ? nil : n
                } label: {
                    Text("\(n)")
                        .font(FATypography.sans(12.5, on ? .semibold : .regular, relativeTo: .caption))
                        .foregroundStyle(on ? FAColor.cream : FAColor.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(on ? accent : FAColor.surfaceMuted)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
