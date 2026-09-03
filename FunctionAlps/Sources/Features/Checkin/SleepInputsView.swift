import SwiftUI

/// Bed / wake times (→ duration) on the left, "time to fall asleep" + "woke during the night"
/// on the right. Duration is only written once the member touches a time.
struct SleepInputsView: View {
    @Binding var specials: SleepSpecials
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: FASpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                timeRow(String(localized: "sleep.bedtime", defaultValue: "Bedtime"), systemImage: "moon.fill", binding: bedBinding)
                timeRow(String(localized: "sleep.wake", defaultValue: "Wake"), systemImage: "sun.max.fill", binding: wakeBinding)
                Text(durationText)
                    .font(FATypography.label)
                    .foregroundStyle(specials.durationMin == nil ? FAColor.inkMuted : accent)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                PillSelectView(title: String(localized: "sleep.latency", defaultValue: "Time to fall asleep"), options: FunctionalSchema.latencyOptions, value: $specials.latency, accent: accent)
                PillSelectView(title: String(localized: "sleep.wakeCount", defaultValue: "Woke during the night"), options: FunctionalSchema.wakeCountOptions, value: $specials.wakeCount, accent: accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeRow(_ label: String, systemImage: String, binding: Binding<Date>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(accent).frame(width: 18)
            Text(label).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            Spacer(minLength: 0)
            DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(accent)
        }
        .accessibilityElement(children: .combine)
    }

    private var durationText: String {
        guard let min = specials.durationMin else {
            return String(localized: "sleep.duration.unset", defaultValue: "Set your night to count its length")
        }
        return String(localized: "sleep.duration", defaultValue: "\(min / 60) h \(min % 60) min in bed")
    }

    // MARK: "HH:mm" ⇄ Date (today's date, local calendar; only the clock part matters)

    private var bedBinding: Binding<Date> {
        Binding(get: { Self.date(from: specials.bedTime ?? "22:00") }, set: { set(bed: Self.string(from: $0), wake: specials.wakeTime ?? "06:30") })
    }
    private var wakeBinding: Binding<Date> {
        Binding(get: { Self.date(from: specials.wakeTime ?? "06:30") }, set: { set(bed: specials.bedTime ?? "22:00", wake: Self.string(from: $0)) })
    }

    private func set(bed: String, wake: String) {
        specials.bedTime = bed
        specials.wakeTime = wake
        specials.durationMin = Self.windowMinutes(bed: bed, wake: wake)
    }

    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return ((parts[0] * 60 + parts[1]) % 1440 + 1440) % 1440
    }

    /// Length of the night, wrapping past midnight (bed 22:00 → wake 06:30 = 510).
    static func windowMinutes(bed: String, wake: String) -> Int? {
        guard let b = minutes(bed), let w = minutes(wake) else { return nil }
        return (w - b + 1440) % 1440
    }

    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func date(from hhmm: String) -> Date {
        let m = minutes(hhmm) ?? 0
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
}
