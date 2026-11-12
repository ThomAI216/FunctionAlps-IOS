import SwiftUI

/// "Feeling for the day": three sliders — mood, felt energy, motivation — each with the pills its value asks:
/// low (< 40) "Why might it be low?", good (>= 60) "What helped?", nothing in between. Its own data (`patient_day_feelings`),
/// never the daily check-in's mood or energy.
struct DayFeelingCard: View {
    @Bindable var model: MorningCheckinViewModel

    private static let whyAccent = Color(hex: 0xD97706)

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "feeling.title", defaultValue: "Feeling for the day"))
                    .font(FATypography.title).foregroundStyle(FAColor.ink)
                Text(String(localized: "feeling.subtitle", defaultValue: "How you feel right now, before the day starts."))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    .padding(.top, 2).padding(.bottom, 6)
                ForEach(Array(DayFeelingSchema.Metric.allCases.enumerated()), id: \.element) { index, metric in
                    if index > 0 { Divider().overlay(FAColor.separator).padding(.vertical, 8) }
                    block(metric)
                }
            }
        }
        .id("showcase.feeling")
    }

    @ViewBuilder
    private func block(_ metric: DayFeelingSchema.Metric) -> some View {
        let value = model.value(metric)
        FunctionalSliderView(spec: DayFeelingSchema.slider(metric), value: Binding(get: { model.value(metric) }, set: { model.set(metric, $0) }))
        if let ask = DayFeelingSchema.ask(for: value) {
            PillGroupView(
                title: DayFeelingSchema.title(ask),
                options: DayFeelingSchema.options(metric, ask),
                isOn: { model.isPillOn(metric, ask, $0) },
                onToggle: { model.togglePill(metric, ask, $0) },
                accent: ask == .why ? Self.whyAccent : FAColor.forestSoft
            )
        }
    }
}
