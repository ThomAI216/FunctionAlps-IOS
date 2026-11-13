import SwiftUI

/// The supplements' small shared pieces: the "Taken" switch, the adherence block, the 14-day strip, the icon tile.
enum SupplementPalette {
    /// The supplement blue of the designs (`#2C5F99`) — the dose line and the adherence figure.
    static let blue = Color(hex: 0x2C5F99)
    static let blueSoft = Color(hex: 0x3F7FC4)

    /// The observance band, as an accent only — the written "11 of 14 days" says it all.
    static func accent(_ band: SupplementLogic.Band?) -> Color {
        switch band {
        case .red: FAColor.danger
        case .orange: FAColor.warning
        case .blue: blueSoft
        case .green: FAColor.forestSoft
        case nil: blueSoft
        }
    }
}

/// The pill tile that fronts a supplement.
struct SupplementIcon: View {
    var body: some View {
        Image(systemName: "pills.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SupplementPalette.blue)
            .frame(width: 28, height: 28)
            .background(SupplementPalette.blueSoft.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The "Taken" switch of Home's rows (mockup `iOSHome`): a capsule with a check when taken — the mark and the word
/// say it, not only the green. The whole capsule is the hit area (44 pt tall).
struct SupplementTakenButton: View {
    let taken: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .accessibilityHidden(true)
                Text(String(localized: "supp.taken", defaultValue: "Taken"))
                    .font(FATypography.sans(11.5, .semibold, relativeTo: .caption))
            }
            .foregroundStyle(taken ? Color.white : FAColor.inkSecondary)
            .padding(.leading, 6).padding(.trailing, 11).padding(.vertical, 5)
            .background(taken ? FAColor.accent : FAColor.ink.opacity(0.07), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "supp.a11y.taken", defaultValue: "Taken: \(name)"))
        .accessibilityValue(taken ? String(localized: "supp.a11y.yes", defaultValue: "Yes") : String(localized: "supp.a11y.no", defaultValue: "Not yet"))
        .accessibilityAddTraits(taken ? .isSelected : [])
    }
}

/// "11 of 14 days · 79%" with its bar: words first, the band's colour only an accent.
struct SupplementAdherenceLine: View {
    let supplement: Supplement
    var large = false

    var body: some View {
        if let o = supplement.observance {
            let text = SupplementLogic.adherenceText(o, rule: supplement.rule)
            let accent = SupplementPalette.accent(SupplementLogic.band(o))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(text ?? String(localized: "supp.adherence.none", defaultValue: "Just getting started"))
                        .font(large ? FATypography.display(28, relativeTo: .title) : FATypography.sans(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(large ? FAColor.ink : SupplementPalette.blue)
                    if text != nil, let pct = SupplementLogic.percentText(o) {
                        Text(large ? pct : "· " + pct)
                            .font(FATypography.sans(large ? 14 : 12, large ? .semibold : .regular, relativeTo: .caption))
                            .foregroundStyle(large ? FAColor.ink : FAColor.inkSecondary)
                    }
                }
                if let pct = o.pct {
                    CPProgressBar(fraction: pct, height: large ? 8 : 6, tint: accent)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "supp.a11y.adherence", defaultValue: "How regularly you take it: \(SupplementLogic.adherenceSpoken(o, rule: supplement.rule))"))
        }
    }
}

/// The 14 days, oldest first. Shape tells the days apart: a check = taken, a half = partly, an empty ring = missed,
/// a dash = nothing due, a dotted ring = today, still to take.
struct SupplementStrip: View {
    let days: [Supplement.StripDay]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(days) { day in
                    mark(SupplementLogic.mark(day))
                        .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text(String(localized: "supp.strip.start", defaultValue: "\(days.count) days ago"))
                Spacer()
                Text(String(localized: "supp.strip.today", defaultValue: "Today"))
            }
            .font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "supp.a11y.strip", defaultValue: "The last \(days.count) days: \(summary)"))
    }

    private var summary: String {
        let marks = days.map(SupplementLogic.mark)
        let taken = marks.filter { $0 == .taken }.count, missed = marks.filter { $0 == .missed }.count
        return String(localized: "supp.a11y.strip.summary", defaultValue: "\(taken) taken, \(missed) missed")
    }

    @ViewBuilder
    private func mark(_ m: SupplementLogic.DayMark) -> some View {
        switch m {
        case .taken:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(FAColor.accent)
        case .partial:
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 16)).foregroundStyle(FAColor.accent)
        case .missed:
            Image(systemName: "circle").font(.system(size: 16)).foregroundStyle(FAColor.inkSecondary)
        case .pending:
            Circle().strokeBorder(FAColor.accent, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5])).frame(width: 16, height: 16)
        case .notDue:
            Capsule().fill(FAColor.inkMuted).frame(width: 8, height: 2)
        }
    }
}
