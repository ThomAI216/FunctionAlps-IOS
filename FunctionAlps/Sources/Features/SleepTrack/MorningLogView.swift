import SwiftUI

/// The morning log — `SLP_ASSESS_M01`–`M11`, 60–90 seconds, done on waking.
///
/// The clock fields use the same `DatePicker(.compact)` + `"HH:mm"` bridge as the
/// functional check-in's `SleepInputsView`, and reuse its `minutes(_:)` /
/// `string(from:)` helpers rather than a second copy.
///
/// The watch's readings appear at the top, inside an `inset` glass pane — the
/// design system's existing idiom for Apple Health tiles — and never inside a
/// field below. A device value never fills a member answer.
struct MorningLogView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var log: MorningLog
    let night: SleepNight?
    let nightNumber: Int
    let totalNights: Int
    var onSave: (MorningLog) -> Void = { _ in }

    init(
        log: MorningLog,
        night: SleepNight? = nil,
        nightNumber: Int,
        totalNights: Int,
        onSave: @escaping (MorningLog) -> Void = { _ in }
    ) {
        _log = State(initialValue: log)
        self.night = night
        self.nightNumber = nightNumber
        self.totalNights = totalNights
        self.onSave = onSave
    }

    private let accent = FAColor.forestSoft

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let night { WatchNightPane(night: night) }
                timesCard
                nightCard
                morningCard
                unusualCard
                footnote
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { dismiss() } label: {
                Text("‹ " + String(localized: "sleepTrack.back", defaultValue: "Back"))
                    .font(FATypography.sans(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(FAColor.ink)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "sleepTrack.morning.title", defaultValue: "Last night"))
                    .font(FATypography.display(26, relativeTo: .title))
                    .foregroundStyle(FAColor.ink)
                Spacer()
                Text(String(localized: "sleepTrack.nightOf", defaultValue: "Night \(nightNumber) of \(totalNights)"))
                    .font(FATypography.label)
                    .foregroundStyle(accent)
            }
            Text(String(localized: "sleepTrack.morning.intro", defaultValue: "About ninety seconds. Rough answers are fine — we are after the pattern across the fortnight, not a perfect record of one night."))
                .font(FATypography.sans(13, relativeTo: .subheadline))
                .foregroundStyle(FAColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    // MARK: the times

    private var timesCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 14) {
                cardKicker(String(localized: "sleepTrack.section.times", defaultValue: "The times"))
                timeRow(
                    field: "M01",
                    label: String(localized: "sleepTrack.m01", defaultValue: "Into bed"),
                    systemImage: "bed.double.fill",
                    binding: binding(for: \.inBed, fallback: "22:30")
                )
                Divider().overlay(FAColor.separator)
                timeRow(
                    field: "M02",
                    label: String(localized: "sleepTrack.m02", defaultValue: "Tried to sleep"),
                    systemImage: "moon.fill",
                    hint: String(localized: "sleepTrack.m02.hint", defaultValue: "Lights out — not when you got in, if you read first."),
                    binding: binding(for: \.trySleep, fallback: "23:00")
                )
                Divider().overlay(FAColor.separator)
                timeRow(
                    field: "M06",
                    label: String(localized: "sleepTrack.m06", defaultValue: "Final waking"),
                    systemImage: "sun.horizon.fill",
                    hint: String(localized: "sleepTrack.m06.hint", defaultValue: "The last one, after which you did not go back to sleep."),
                    binding: binding(for: \.finalWake, fallback: "06:30")
                )
                Divider().overlay(FAColor.separator)
                timeRow(
                    field: "M07",
                    label: String(localized: "sleepTrack.m07", defaultValue: "Out of bed"),
                    systemImage: "sun.max.fill",
                    binding: binding(for: \.outOfBed, fallback: "07:00")
                )
                if let window = windowText {
                    Text(window)
                        .font(FATypography.caption)
                        .foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
    }

    private func timeRow(field: String, label: String, systemImage: String, hint: String? = nil, binding: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(accent)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(label)
                    .font(FATypography.sans(14.5, .medium, relativeTo: .body))
                    .foregroundStyle(FAColor.ink)
                Spacer(minLength: 0)
                DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(accent)
            }
            if let hint {
                Text(hint)
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkMuted)
                    .padding(.leading, 28)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    /// Time in bed, wrapping past midnight — the same arithmetic the check-in uses.
    private var windowText: String? {
        guard
            let inBed = log.inBed, let outOfBed = log.outOfBed,
            let minutes = SleepInputsView.windowMinutes(bed: inBed, wake: outOfBed)
        else { return nil }
        return String(localized: "sleepTrack.timeInBed", defaultValue: "\(minutes / 60) h \(minutes % 60) min in bed, end to end")
    }

    // MARK: the night

    private var nightCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 14) {
                cardKicker(String(localized: "sleepTrack.section.night", defaultValue: "The night itself"))

                ChoiceRow(
                    field: "M03",
                    label: String(localized: "sleepTrack.m03", defaultValue: "How long to fall asleep?"),
                    hint: String(localized: "sleepTrack.m03.hint", defaultValue: "A rough number is fine. Never taken from your watch."),
                    options: SleepTrackOptions.latency,
                    selection: $log.latencyMin,
                    accent: accent
                )
                Divider().overlay(FAColor.separator)
                ChoiceRow(
                    field: "M04",
                    label: String(localized: "sleepTrack.m04", defaultValue: "Times you remember waking"),
                    options: SleepTrackOptions.awakenings,
                    selection: $log.awakenings,
                    accent: accent
                )
                Divider().overlay(FAColor.separator)
                ChoiceRow(
                    field: "M05",
                    label: String(localized: "sleepTrack.m05", defaultValue: "Awake in the night, added up"),
                    options: SleepTrackOptions.waso,
                    selection: $log.wasoMin,
                    accent: accent
                )

                Text(String(localized: "sleepTrack.notSure.explainer", defaultValue: "“Not sure” is a real answer and we would rather have it than a guess. It costs that one number for that one night — the rest of the night still counts, and so does the night."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .modifier(FAGlassSurface(cornerRadius: FACornerRadius.sm, inset: true))
            }
        }
    }

    // MARK: this morning

    private var morningCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 18) {
                cardKicker(String(localized: "sleepTrack.section.morning", defaultValue: "This morning"))
                ZeroToTenRow(
                    field: "M08",
                    label: String(localized: "sleepTrack.m08", defaultValue: "How restorative did it feel?"),
                    low: String(localized: "sleepTrack.m08.low", defaultValue: "Not at all"),
                    high: String(localized: "sleepTrack.m08.high", defaultValue: "Extremely"),
                    value: $log.restoration,
                    accent: accent
                )
                ZeroToTenRow(
                    field: "M09",
                    label: String(localized: "sleepTrack.m09", defaultValue: "How sleepy are you right now?"),
                    low: String(localized: "sleepTrack.m09.low", defaultValue: "Fully alert"),
                    high: String(localized: "sleepTrack.m09.high", defaultValue: "Struggling to stay awake"),
                    value: $log.sleepiness,
                    accent: accent
                )
                ZeroToTenRow(
                    field: "M10",
                    label: String(localized: "sleepTrack.m10", defaultValue: "And the night overall?"),
                    low: String(localized: "sleepTrack.m10.low", defaultValue: "Very poor"),
                    high: String(localized: "sleepTrack.m10.high", defaultValue: "Very good"),
                    value: $log.overall,
                    accent: accent
                )
            }
        }
    }

    // MARK: anything unusual

    private var unusualCard: some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                cardKicker(String(localized: "sleepTrack.section.unusual", defaultValue: "Anything unusual?"))
                Text(String(localized: "sleepTrack.m11.hint", defaultValue: "Optional. This is what lets us tell an ordinary night from one that had a reason."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PillGroupView(
                    title: nil,
                    options: SleepTrackOptions.unusual,
                    isOn: { log.unusual.contains($0) },
                    onToggle: { key in
                        if key == SleepTrackOptions.nothingUnusual {
                            log.unusual = log.unusual.contains(key) ? [] : [key]
                        } else {
                            log.unusual.remove(SleepTrackOptions.nothingUnusual)
                            if log.unusual.contains(key) { log.unusual.remove(key) } else { log.unusual.insert(key) }
                        }
                    },
                    accent: accent
                )
            }
        }
    }

    private var footnote: some View {
        Text(String(localized: "sleepTrack.morning.footnote", defaultValue: "You can correct any of this until tomorrow evening. Nothing here changes your plan — we are only watching, for another eight mornings."))
            .font(FATypography.caption)
            .foregroundStyle(FAColor.inkMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, FASpacing.md)
            .padding(.top, 4)
    }

    private var saveBar: some View {
        FAButton(title: String(localized: "sleepTrack.logNight", defaultValue: "Log this night")) {
            var saved = log
            saved.completedAt = .now
            onSave(saved)
            dismiss()
        }
        .padding(.horizontal, FASpacing.md)
        .padding(.bottom, FASpacing.sm)
    }

    private func cardKicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(FATypography.label)
            .tracking(0.8)
            .foregroundStyle(FAColor.brand)
    }

    /// `"HH:mm"` ⇄ `Date`, borrowing the check-in's bridge so there is one implementation.
    private func binding(for keyPath: WritableKeyPath<MorningLog, String?>, fallback: String) -> Binding<Date> {
        Binding(
            get: { SleepInputsView.date(from: log[keyPath: keyPath] ?? fallback) },
            set: { log[keyPath: keyPath] = SleepInputsView.string(from: $0) }
        )
    }
}

// MARK: - the watch pane

/// What Apple Health already holds for the night, in the `inset` glass the design
/// system reserves for Health tiles — so the member can see at a glance that this
/// is the watch talking and the white cards below are them.
struct WatchNightPane: View {
    let night: SleepNight

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "applewatch")
                        .foregroundStyle(FAColor.inkSecondary)
                        .accessibilityHidden(true)
                    Text(String(localized: "sleepTrack.watch.title", defaultValue: "Your watch already sent last night").uppercased())
                        .font(FATypography.label)
                        .tracking(0.8)
                        .foregroundStyle(FAColor.inkSecondary)
                }
                HStack(alignment: .top, spacing: 10) {
                    watchStat(HealthFormat.hours(night.asleepSeconds / 3600), String(localized: "sleepTrack.watch.asleep", defaultValue: "it estimates asleep"))
                    if let pct = night.efficiencyPct {
                        watchStat("\(pct) %", String(localized: "sleepTrack.watch.efficiency", defaultValue: "its efficiency figure"))
                    }
                    watchStat("\(night.interruptions)", String(localized: "sleepTrack.watch.interruptions", defaultValue: "awake stretches it saw"))
                }
                Text(String(localized: "sleepTrack.watch.caveat", defaultValue: "Your watch knows how long, and roughly when it thinks you were asleep. It cannot know when you got into bed, when you gave up on your book, or how the night felt. That is the part only you can give us."))
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func watchStat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(FATypography.sans(17, .semibold, relativeTo: .headline))
                .foregroundStyle(FAColor.ink)
            Text(caption)
                .font(FATypography.sans(10.5, relativeTo: .caption2))
                .foregroundStyle(FAColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .modifier(FAGlassSurface(cornerRadius: FACornerRadius.sm, inset: true))
    }
}
