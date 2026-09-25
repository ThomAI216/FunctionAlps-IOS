import SwiftUI

/// The block a running Stress track adds to the END of the morning or evening
/// check-in — spec §3's nine items, and no others. Brief §6 is the UI spec.
///
/// It is not a screen. `CheckinMomentView` places it after its own sections and
/// before Save; the one Save button saves both (brief §9, steps 4–5).
///
/// What it must keep:
///  1. **Every item can be skipped, and a chosen answer tapped again clears it.** A
///     skipped item is NULL for that one metric on that one day, never the day.
///  2. **Nothing is scored and nothing is shown back.** No total, no ramp, no "you
///     recovered well". `FAColor.scale` is deliberately absent: one accent for the
///     chosen value, neutral for the rest.
///  3. **Mood and calm are not asked here.** The check-in above already asks them, and
///     calm stays calm — this block never mentions a stress number.
///  4. **Follow-ups live behind their "yes".** S7's switch-off rating only on an
///     obligation day; S8's what and how-much only when they did something restorative.
///  5. **Social connection is one gentle yes/no.** No rating of anyone's relationships.
struct StressCheckinAdditionsView: View {
    let context: StressCheckinContext
    @Binding var draft: StressCheckinDraft

    private let accent = FAColor.forestSoft

    var body: some View {
        VStack(alignment: .leading, spacing: FASpacing.sm) {
            divider
            FACard {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    switch context.part {
                    case .morning: morningItems
                    case .evening: eveningItems
                    }
                }
            }
        }
    }

    // MARK: header

    /// "added while your track runs" — the block is the track's, visibly, so nobody
    /// mistakes it for the check-in growing for good.
    private var divider: some View {
        HStack(spacing: FASpacing.sm) {
            Rectangle().fill(accent.opacity(0.25)).frame(height: 1)
            Text(String(localized: "stressTrack.block.divider", defaultValue: "added while your track runs"))
                .font(FATypography.sans(10.5, .semibold, relativeTo: .caption2))
                .foregroundStyle(accent)
                .fixedSize()
            Rectangle().fill(accent.opacity(0.25)).frame(height: 1)
        }
        .padding(.top, 6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: FASpacing.sm) {
                Text(String(localized: "stressTrack.block.eyebrow", defaultValue: "For your \(context.totalDays)-day stress track"))
                    .font(FATypography.label)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                // A count, never a conclusion (the Sleep rule: nothing is shown before
                // the window closes).
                Text(String(localized: "stressTrack.block.day", defaultValue: "Day \(context.dayNumber) of \(context.totalDays)"))
                    .font(FATypography.label)
                    .foregroundStyle(accent)
            }
            Text(
                context.part == .morning
                    ? String(localized: "stressTrack.block.morning", defaultValue: "Three quick ones · about ten seconds")
                    : String(localized: "stressTrack.block.evening", defaultValue: "A few more · under a minute")
            )
            .font(FATypography.sans(13.5, .medium, relativeTo: .callout))
            .foregroundStyle(FAColor.ink)
            Text(String(localized: "stressTrack.block.skip", defaultValue: "Skip any you like. These go away by themselves after day \(context.totalDays)."))
                .font(FATypography.caption)
                .foregroundStyle(FAColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let provenance {
                Text(provenance)
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.bottom, 4)
    }

    /// Show the other surface's state: a day answered on the web is prefilled here and
    /// says so, rather than being asked again or silently overwritten.
    private var provenance: String? {
        guard draft.existedOnServer, draft.lastUpdatedVia == .web, let at = draft.lastUpdatedAt else { return nil }
        let time = at.formatted(date: .omitted, time: .shortened)
        return String(localized: "stressTrack.block.fromWeb", defaultValue: "You last saved these on the web at \(time). Change anything that’s off.")
    }

    // MARK: morning — S1–S3

    @ViewBuilder
    private var morningItems: some View {
        StressItem(
            id: "S1",
            question: String(localized: "stressTrack.s1", defaultValue: "How recovered do you feel this morning?")
        ) {
            StressScaleRow(
                value: $draft.morning.recovered,
                low: String(localized: "stressTrack.s1.low", defaultValue: "Not at all"),
                high: String(localized: "stressTrack.s1.high", defaultValue: "Completely"),
                accent: accent
            )
        }
        StressItem(
            id: "S2",
            question: String(localized: "stressTrack.s2", defaultValue: "Are you unwell or feverish today?"),
            // A confounder, never a flag — and the member is told what it does.
            hint: String(localized: "stressTrack.s2.hint", defaultValue: "If you are, we keep today. We just won’t compare it with your other days.")
        ) {
            StressChoiceChips(options: Self.yesNo, selection: draft.morning.unwell, accent: accent) { draft.morning.unwell = $0 }
        }
        StressItem(
            id: "S3",
            question: String(localized: "stressTrack.s3", defaultValue: "Any alcohol last evening?"),
            hint: String(localized: "stressTrack.s3.hint", defaultValue: "Just yes or no, no amounts."),
            isLast: true
        ) {
            StressChoiceChips(options: Self.yesNo, selection: draft.morning.alcoholLastEvening, accent: accent) { draft.morning.alcoholLastEvening = $0 }
        }
    }

    // MARK: evening — S4–S9

    @ViewBuilder
    private var eveningItems: some View {
        StressItem(
            id: "S4",
            question: String(localized: "stressTrack.s4", defaultValue: "Today, at its most stressful — how intense did it get?")
        ) {
            StressScaleRow(
                value: $draft.evening.peak,
                low: String(localized: "stressTrack.s4.low", defaultValue: "Hardly at all"),
                high: String(localized: "stressTrack.s4.high", defaultValue: "As intense as it gets"),
                accent: accent
            )
        }

        StressItem(
            id: "S5",
            question: String(localized: "stressTrack.s5", defaultValue: "After the hardest moment, how long until you felt close to normal?")
        ) {
            VStack(alignment: .leading, spacing: FASpacing.sm) {
                // The six ordinal bands…
                StressChoiceChips(
                    options: RecoveryLatencyBand.measured.map { ($0, $0.label) },
                    selection: draft.evening.recoveryLatency,
                    accent: accent
                ) { draft.evening.recoveryLatency = $0 }
                // …and, apart and muted, the answer to a different question. A quiet day
                // is not a fast recovery, and must not look like one of the bands.
                StressChoiceChips(
                    options: [(RecoveryLatencyBand.noStressor, RecoveryLatencyBand.noStressor.label)],
                    selection: draft.evening.recoveryLatency,
                    muted: [.noStressor],
                    accent: accent
                ) { draft.evening.recoveryLatency = $0 }
            }
        }

        StressItem(
            id: "S6",
            question: String(localized: "stressTrack.s6", defaultValue: "How much are you still carrying right now?"),
            hint: String(localized: "stressTrack.s6.hint", defaultValue: "Whatever from today is still with you.")
        ) {
            StressScaleRow(
                value: $draft.evening.carryover,
                low: String(localized: "stressTrack.s6.low", defaultValue: "Nothing"),
                high: String(localized: "stressTrack.s6.high", defaultValue: "A great deal"),
                accent: accent
            )
        }

        // S7 is the day-type chip (decision 2026-09-25), shown to EVERY member: coverage
        // and the free-vs-obligation pattern need a day type from everyone. The work
        // gate (`showsWorkDetachment`) governs only the switch-off question under it.
        StressItem(
            id: "S7",
            // The Nutrition day close's D02 wording, verbatim (DayCloseView.swift), so the
            // one shared axis is asked the same way in every track.
            question: String(localized: "stressTrack.s7.dayType", defaultValue: "What kind of day was today?")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                StressChoiceChips(
                    options: NutritionDayType.allCases.map { ($0, Self.dayTypeLabel($0)) },
                    selection: draft.evening.dayType,
                    accent: accent
                ) { draft.evening.setDayType($0) }

                // Only on an obligation day. A free day hides it: a day off is not
                // "switched off well", and it is stored as NULL.
                if draft.evening.dayType == .obligation && context.showsWorkDetachment {
                    StressFollowUp(text: String(localized: "stressTrack.s7.switchOff", defaultValue: "How well have you switched off from work?"))
                    StressScaleRow(
                        // A rating clears "I didn't work today" (setWorkDetachment).
                        value: Binding(
                            get: { draft.evening.workDetachment },
                            set: { draft.evening.setWorkDetachment($0) }
                        ),
                        low: String(localized: "stressTrack.s7.low", defaultValue: "Not at all, still in it"),
                        high: String(localized: "stressTrack.s7.high", defaultValue: "Completely"),
                        accent: accent
                    )
                    // For an obligation day that wasn't work (caring, errands, admin). Apart
                    // and muted, as "no stressor" is under S5: it answers a different
                    // question, and is stored as the same NULL a skip is.
                    StressChoiceChips(
                        options: [(true, String(localized: "stressTrack.s7.no", defaultValue: "I didn’t work today"))],
                        selection: draft.evening.didNotWork ? Optional(true) : nil,
                        muted: [true],
                        accent: accent
                    ) { draft.evening.setDidNotWork($0 == true) }
                }
            }
        }

        StressItem(
            id: "S8",
            question: String(localized: "stressTrack.s8", defaultValue: "Did you do anything today on purpose to recharge?"),
            hint: String(localized: "stressTrack.s8.hint", defaultValue: "Anything deliberate counts, even ten quiet minutes.")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                StressChoiceChips(options: Self.yesNo, selection: draft.evening.restorative, accent: accent) {
                    draft.evening.setRestorative($0)
                }

                if draft.evening.restorative == true {
                    StressFollowUp(text: String(localized: "stressTrack.s8.what", defaultValue: "What was it?"))
                    FlowLayout(spacing: 7) {
                        ForEach(RestorativeType.allCases) { type in
                            PillButton(label: type.label, hue: accent, on: draft.evening.contains(type)) {
                                draft.evening.toggle(type)
                            }
                        }
                    }
                    StressFollowUp(text: String(localized: "stressTrack.s8.effect", defaultValue: "How much did it help, in the moment?"))
                    StressScaleRow(
                        value: $draft.evening.restorativeEffect,
                        low: String(localized: "stressTrack.s8.low", defaultValue: "Not at all"),
                        high: String(localized: "stressTrack.s8.high", defaultValue: "A lot"),
                        accent: accent
                    )
                }
            }
        }

        StressItem(
            id: "S9",
            question: String(localized: "stressTrack.s9", defaultValue: "Did you have at least one conversation today that felt meaningful?"),
            hint: String(localized: "stressTrack.s9.hint", defaultValue: "In person, on the phone, or a message that turned into a real exchange. Whatever counted for you."),
            isLast: true
        ) {
            StressChoiceChips(options: Self.yesNo, selection: draft.evening.meaningfulConnection, accent: accent) {
                draft.evening.meaningfulConnection = $0
            }
        }
    }

    private static var yesNo: [(Bool, String)] {
        [
            (true, String(localized: "stressTrack.yes", defaultValue: "Yes")),
            (false, String(localized: "stressTrack.no", defaultValue: "No")),
        ]
    }

    /// The Nutrition day close's chip labels, verbatim (`DayCloseView`, D02:
    /// `nutrition.day.obligation` / `nutrition.day.free`). French must match those keys.
    private static func dayTypeLabel(_ type: NutritionDayType) -> String {
        switch type {
        case .obligation: String(localized: "stressTrack.dayType.obligation", defaultValue: "Work or obligation")
        case .free: String(localized: "stressTrack.dayType.free", defaultValue: "A free day")
        }
    }
}

// MARK: - Pieces

/// One item: its stable field id beside the question (so a bug report or a
/// practitioner can name the field exactly — the Sleep track's M01…M11 idiom), an
/// optional hint, then the control.
private struct StressItem<Content: View>: View {
    let id: String
    let question: String
    var hint: String? = nil
    var isLast = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(id)
                        // FATypography has no mono face; the system one keeps the ids aligned.
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(FAColor.inkMuted)
                        .frame(width: 20, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(question)
                        .font(FATypography.sans(14.5, .medium, relativeTo: .body))
                        .foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                if let hint {
                    Text(hint)
                        .font(FATypography.caption)
                        .foregroundStyle(FAColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 28)
                }
                content
                    .padding(.leading, 28)
                    .padding(.top, 2)
            }
            .padding(.vertical, 14)
            if !isLast {
                Divider().overlay(FAColor.separator)
            }
        }
    }
}

/// The question a "yes" opens, set inside its parent item.
private struct StressFollowUp: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FATypography.sans(14, .medium, relativeTo: .subheadline))
            .foregroundStyle(FAColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

/// Single choice, as the check-in's own pills. Tapping the chosen one clears it.
/// `muted` options answer a different question ("nothing stressful", "didn't work")
/// and are drawn in the neutral hue rather than the accent.
private struct StressChoiceChips<Value: Hashable>: View {
    let options: [(Value, String)]
    let selection: Value?
    var muted: Set<Value> = []
    let accent: Color
    let onSelect: (Value?) -> Void

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = selection == option.0
                PillButton(label: option.1, hue: muted.contains(option.0) ? FAColor.inkSecondary : accent, on: on) {
                    onSelect(on ? nil : option.0)
                }
            }
        }
    }
}

/// 0–10. One accent for the chosen value and nothing for the rest — deliberately NOT
/// `FAColor.scale`: a 3 here is an observation, not a failing grade, and a ramp
/// repeated down the check-in lets a member assemble by eye the score this pillar
/// refuses to give. Tapping the chosen value again clears it (NULL, never 0).
private struct StressScaleRow: View {
    @Binding var value: Int?
    let low: String
    let high: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0...10, id: \.self) { n in
                    let on = value == n
                    Button {
                        value = on ? nil : n
                    } label: {
                        Text("\(n)")
                            .font(FATypography.sans(12.5, on ? .semibold : .regular, relativeTo: .caption))
                            .foregroundStyle(on ? FAColor.cream : FAColor.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(on ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(on ? accent : FAColor.separator, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n)")
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Text(low)
                Spacer(minLength: 0)
                Text(high).multilineTextAlignment(.trailing)
            }
            .font(FATypography.sans(10.5, relativeTo: .caption2))
            .foregroundStyle(FAColor.inkMuted)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Previews

private enum StressAdditionsSample {
    static let window = StressTrackWindow(assessmentId: "preview", protocolDays: 14, startedOn: "2026-09-20", lastDay: "2026-10-03")

    static func context(_ part: StressDiaryPart, showsWorkDetachment: Bool = true) -> StressCheckinContext {
        StressCheckinContext(window: window, part: part, dayNumber: 6, showsWorkDetachment: showsWorkDetachment, original: StressCheckinDraft(localDate: "2026-09-25"))
    }

    /// The evening the MEMBERS web mockup shows, so the two surfaces can be compared
    /// side by side. S3 is left unanswered on purpose: that is what a skip looks like.
    static var answered: StressCheckinDraft {
        var d = StressCheckinDraft(localDate: "2026-09-25")
        d.morning = .init(recovered: 4, unwell: false, alcoholLastEvening: nil)
        d.evening.peak = 7
        d.evening.recoveryLatency = .from1to3h
        d.evening.carryover = 5
        d.evening.setDayType(.obligation)
        d.evening.setWorkDetachment(3)
        d.evening.setRestorative(true)
        d.evening.toggle(.walking)
        d.evening.restorativeEffect = 6
        d.evening.meaningfulConnection = true
        return d
    }

    /// The same evening on a free day: S7 shows the chip and nothing under it.
    static var freeDay: StressCheckinDraft {
        var d = answered
        d.evening.setDayType(.free)
        return d
    }

    /// An obligation day, blank otherwise: what a member whose questionnaire never
    /// named work sees (with the gate closed, no switch-off question).
    static var obligationOnly: StressCheckinDraft {
        var d = StressCheckinDraft(localDate: "2026-09-25")
        d.evening.setDayType(.obligation)
        return d
    }
}

private struct StressAdditionsPreviewHost: View {
    let context: StressCheckinContext
    @State var draft: StressCheckinDraft

    var body: some View {
        ScrollView {
            StressCheckinAdditionsView(context: context, draft: $draft)
                .padding(.horizontal, FASpacing.md)
                .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
    }
}

#Preview("Stress additions · morning") {
    StressAdditionsPreviewHost(context: StressAdditionsSample.context(.morning), draft: StressAdditionsSample.answered)
}

#Preview("Stress additions · evening") {
    StressAdditionsPreviewHost(context: StressAdditionsSample.context(.evening), draft: StressAdditionsSample.answered)
}

#Preview("Stress additions · evening, free day") {
    StressAdditionsPreviewHost(context: StressAdditionsSample.context(.evening), draft: StressAdditionsSample.freeDay)
}

#Preview("Stress additions · evening, obligation day, work never named") {
    StressAdditionsPreviewHost(
        context: StressAdditionsSample.context(.evening, showsWorkDetachment: false),
        draft: StressAdditionsSample.obligationOnly
    )
}
