import SwiftUI

/// Last night, two ways (owner, 2026-11-10):
/// - a wearable or Apple Health recorded it → the night as it was recorded: bed → wake, time in bed, time
///   asleep, named by its source, with "Adjust" opening the dial for anything that's off;
/// - nothing recorded it → the 24-hour dial (moon = bedtime, sun = wake), the member slides the two.
/// Beside it, either way: how long falling asleep took and how often they woke — whose follow-ups ("what kept
/// you up?", "what helped?", "why did you wake?") the dimension card shows right under. Duration is only
/// written once the member touches a time, or a source gave one.
struct SleepInputsView: View {
    @Binding var specials: SleepSpecials
    let accent: Color
    /// The night a wearable or Apple Health recorded, when one did.
    var recorded: WearableNight? = nil

    @State private var adjusting = false
    @Environment(\.dynamicTypeSize) private var typeSize

    static let defaultBed = "22:30"
    static let defaultWake = "06:30"

    var body: some View {
        if let recorded, recorded.bedTime != nil || recorded.durationMin != nil {
            VStack(alignment: .leading, spacing: 10) {
                recordedPanel(recorded)
                if adjusting {
                    SleepDialView(bed: bedMinutes, wake: wakeMinutes, isSet: true, accent: accent, onChange: setNight)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                bandPills(compact: false)
            }
            .animation(.easeInOut(duration: 0.22), value: adjusting)
        } else {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                VStack(spacing: 6) {
                    SleepDialView(bed: bedMinutes, wake: wakeMinutes, isSet: specials.durationMin != nil, accent: accent, onChange: setNight)
                    clockLine
                }
                .frame(width: typeSize.isAccessibilitySize ? nil : 150)
                .frame(maxWidth: typeSize.isAccessibilitySize ? 220 : nil)
                bandPills(compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Recorded night

    private func recordedPanel(_ night: WearableNight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: WearableVendor.sourceSymbol(night.sourceId))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WearableVendor.sourceTint(night.sourceId))
                Text(sourceLine(night))
                    .font(FATypography.sans(11.5, .medium, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    adjusting.toggle()
                } label: {
                    Text(adjusting ? String(localized: "sleep.recorded.done", defaultValue: "Done") : String(localized: "sleep.recorded.adjust", defaultValue: "Adjust"))
                        .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if specials.bedTime != nil || specials.wakeTime != nil {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    clockBlock(systemImage: "moon.fill", label: String(localized: "sleep.bedtime", defaultValue: "Bedtime"), value: specials.bedTime)
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted).accessibilityHidden(true)
                    clockBlock(systemImage: "sun.max.fill", label: String(localized: "sleep.wake", defaultValue: "Wake"), value: specials.wakeTime)
                }
            }
            HStack(spacing: 8) {
                if let inBed = specials.durationMin {
                    statChip(String(localized: "sleep.recorded.inBed", defaultValue: "In bed"), SleepDialMath.durationLabel(inBed))
                }
                if let asleep = night.asleepMin {
                    statChip(String(localized: "sleep.recorded.asleep", defaultValue: "Asleep"), SleepDialMath.durationLabel(asleep))
                }
                if let inBed = specials.durationMin, let asleep = night.asleepMin, inBed > 0 {
                    statChip(String(localized: "sleep.recorded.efficiency", defaultValue: "Efficiency"), "\(min(100, Int((100 * Double(asleep) / Double(inBed)).rounded()))) %")
                }
            }
        }
        .padding(12)
        .modifier(FAGlassSurface(cornerRadius: 14, inset: true))
    }

    private func sourceLine(_ night: WearableNight) -> String {
        let source = WearableVendor.sourceName(night.sourceId)
        if night.bedTime == nil || night.wakeTime == nil {
            return String(localized: "sleep.recorded.noClock", defaultValue: "From \(source) · it didn't record when you went to bed · tap Adjust")
        }
        if let bed = night.bedTime, let wake = night.wakeTime, specials.bedTime != bed || specials.wakeTime != wake {
            // The member moved the times: say so, and keep what the source saw beside it.
            return String(localized: "sleep.recorded.adjusted", defaultValue: "Adjusted · \(source) recorded \(bed) → \(wake)")
        }
        if night.clockIsGuessed {
            // The row carried no timezone: the times are this phone's reading of the instant — only right if the
            // night was spent in this timezone. Say so rather than look certain.
            return String(localized: "sleep.recorded.guessed", defaultValue: "From \(source) · read in this timezone · check the times")
        }
        return String(localized: "sleep.recorded.from", defaultValue: "From \(source)")
    }

    private func clockBlock(systemImage: String, label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(label, systemImage: systemImage)
                .font(FATypography.sans(10.5, .medium, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                .labelStyle(TintedIconLabel(tint: accent))
            Text(value ?? "–")
                .font(FATypography.display(24, relativeTo: .title2)).foregroundStyle(FAColor.ink).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(FATypography.sans(9.5, .medium, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
            Text(value).font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Shared

    /// "22:30 → 06:30" under the dial, once set.
    private var clockLine: some View {
        Group {
            if specials.durationMin != nil {
                Text("\(specials.bedTime ?? Self.defaultBed) → \(specials.wakeTime ?? Self.defaultWake)")
                    .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(accent).monospacedDigit()
            } else {
                Text(String(localized: "sleep.duration.unset", defaultValue: "Set your night to count its length"))
                    .font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FAColor.inkMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Time to fall asleep · woke during the night — the bands the follow-up questions hang on.
    private func bandPills(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PillSelectView(title: String(localized: "sleep.latency", defaultValue: "Time to fall asleep"), options: FunctionalSchema.latencyOptions, value: $specials.latency, accent: accent)
            PillSelectView(title: String(localized: "sleep.wakeCount", defaultValue: "Woke during the night"), options: FunctionalSchema.wakeCountOptions, value: $specials.wakeCount, accent: accent)
        }
        .padding(.top, compact ? -12 : -6)
    }

    private var bedMinutes: Int { SleepSpecials.minutes(specials.bedTime ?? Self.defaultBed) ?? 22 * 60 + 30 }
    private var wakeMinutes: Int { SleepSpecials.minutes(specials.wakeTime ?? Self.defaultWake) ?? 6 * 60 + 30 }

    private func setNight(bed: Int, wake: Int) {
        let b = SleepDialView.clock(bed), w = SleepDialView.clock(wake)
        specials.bedTime = b
        specials.wakeTime = w
        specials.durationMin = SleepSpecials.windowMinutes(bed: b, wake: w)
    }
}

/// A label whose icon takes a tint and whose title keeps the text colour.
private struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
