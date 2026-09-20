import SwiftUI

/// The diary's answer sets, and the two input rows the morning log is built from.
///
/// `nil` is "not sure" throughout — an answer the instrument deliberately offers,
/// carried as an absent value rather than a sentinel, so nothing downstream can
/// mistake an unknown for a zero.
enum SleepTrackOptions {
    /// Midpoint minutes for each band; `nil` is "not sure".
    static let latency: [(label: String, value: Int?)] = [
        (String(localized: "sleepTrack.latency.under15", defaultValue: "Under 15 min"), 8),
        (String(localized: "sleepTrack.latency.15to30", defaultValue: "15–30"), 22),
        (String(localized: "sleepTrack.latency.30to45", defaultValue: "30–45"), 37),
        (String(localized: "sleepTrack.latency.45to60", defaultValue: "45–60"), 52),
        (String(localized: "sleepTrack.latency.1to2h", defaultValue: "1–2 h"), 90),
        (String(localized: "sleepTrack.latency.over2h", defaultValue: "Over 2 h"), 150),
        (notSureLabel, nil),
    ]

    static let awakenings: [(label: String, value: Int?)] = [
        ("0", 0), ("1", 1), ("2", 2), ("3", 3), ("4", 4),
        (String(localized: "sleepTrack.awakenings.5plus", defaultValue: "5+"), 5),
        (notSureLabel, nil),
    ]

    static let waso: [(label: String, value: Int?)] = [
        (String(localized: "sleepTrack.waso.none", defaultValue: "None"), 0),
        (String(localized: "sleepTrack.waso.under15", defaultValue: "Under 15 min"), 8),
        (String(localized: "sleepTrack.waso.15to30", defaultValue: "15–30"), 22),
        (String(localized: "sleepTrack.waso.30to60", defaultValue: "30–60"), 45),
        (String(localized: "sleepTrack.waso.1to2h", defaultValue: "1–2 h"), 90),
        (String(localized: "sleepTrack.waso.over2h", defaultValue: "Over 2 h"), 150),
        (notSureLabel, nil),
    ]

    static let notSureLabel = String(localized: "sleepTrack.notSure", defaultValue: "Not sure")
    static let nothingUnusual = "nothing"

    /// M11. Three of these keys feed deterministic diary-side safety rules
    /// (`DIARY_BREATHING_CONCERN`, `DIARY_PARASOMNIA_CONCERN`) — the copy may
    /// change, the keys may not.
    static let unusual: [PillOption] = [
        PillOption(key: nothingUnusual, label: String(localized: "sleepTrack.unusual.nothing", defaultValue: "Nothing unusual")),
        PillOption(key: "illness", label: String(localized: "sleepTrack.unusual.illness", defaultValue: "Illness")),
        PillOption(key: "pain", label: String(localized: "sleepTrack.unusual.pain", defaultValue: "Pain")),
        PillOption(key: "reflux", label: String(localized: "sleepTrack.unusual.reflux", defaultValue: "Reflux")),
        PillOption(key: "hot_flushes", label: String(localized: "sleepTrack.unusual.hotFlushes", defaultValue: "Hot flushes")),
        PillOption(key: "breathing", label: String(localized: "sleepTrack.unusual.breathing", defaultValue: "Breathing or snoring")),
        PillOption(key: "household", label: String(localized: "sleepTrack.unusual.household", defaultValue: "Child, pet or partner")),
        PillOption(key: "noise", label: String(localized: "sleepTrack.unusual.noise", defaultValue: "Noise")),
        PillOption(key: "light", label: String(localized: "sleepTrack.unusual.light", defaultValue: "Light")),
        PillOption(key: "temperature", label: String(localized: "sleepTrack.unusual.temperature", defaultValue: "Too warm or cold")),
        PillOption(key: "travel", label: String(localized: "sleepTrack.unusual.travel", defaultValue: "Travel or a new bed")),
        PillOption(key: "alcohol", label: String(localized: "sleepTrack.unusual.alcohol", defaultValue: "Alcohol, unlike usual")),
        PillOption(key: "medication", label: String(localized: "sleepTrack.unusual.medication", defaultValue: "Medication, unlike usual")),
        PillOption(key: "parasomnia", label: String(localized: "sleepTrack.unusual.parasomnia", defaultValue: "A nightmare or unusual behaviour")),
    ]
}

/// A labelled band picker where "not sure" is a peer of every other answer, not a
/// way out of the question. Rendered with the check-in's pills so it feels like
/// the rest of the app.
struct ChoiceRow: View {
    let field: String
    let label: String
    var hint: String? = nil
    let options: [(label: String, value: Int?)]
    @Binding var selection: Int?
    let accent: Color

    /// Tracks "the member chose Not sure" apart from "the member has not answered".
    @State private var answered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SleepFieldLabel(field: field, label: label)
            if let hint {
                Text(hint)
                    .font(FATypography.caption)
                    .foregroundStyle(FAColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 7) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let isNotSure = option.value == nil
                    let on = answered && selection == option.value
                    PillButton(
                        label: option.label,
                        hue: isNotSure ? FAColor.inkSecondary : accent,
                        on: on
                    ) {
                        selection = option.value
                        answered = true
                    }
                }
            }
        }
    }
}

/// A 0–10 row. One accent for the chosen value and nothing for the rest:
/// deliberately NOT `FAColor.scale`, because a 3 here is an observation and not a
/// failing grade, and thirteen of those ramps down a results page reassemble the
/// score this pillar refuses to give.
struct ZeroToTenRow: View {
    let field: String
    let label: String
    let low: String
    let high: String
    @Binding var value: Int?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SleepFieldLabel(field: field, label: label)
            HStack(spacing: 4) {
                ForEach(0...10, id: \.self) { i in
                    Button {
                        value = i
                    } label: {
                        Text("\(i)")
                            .font(value == i ? FATypography.sans(13, .bold, relativeTo: .caption) : FATypography.sans(12.5, relativeTo: .caption))
                            .foregroundStyle(value == i ? Color.white : FAColor.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(value == i ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(value == i ? accent : FAColor.separator, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(i)")
                    .accessibilityAddTraits(value == i ? [.isSelected] : [])
                }
            }
            HStack {
                Text(low).font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted)
                Spacer()
                Text(high).font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The field id sits beside its question so a practitioner reading over a member's
/// shoulder — or a bug report — can name the field exactly.
struct SleepFieldLabel: View {
    let field: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(field)
                .font(FATypography.sans(10, .semibold, relativeTo: .caption2))
                .foregroundStyle(FAColor.inkMuted)
            Text(label)
                .font(FATypography.sans(14.5, .medium, relativeTo: .body))
                .foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
