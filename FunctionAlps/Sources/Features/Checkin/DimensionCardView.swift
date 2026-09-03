import SwiftUI

/// One functional dimension: header score, then each section (sleep inputs / sliders) followed
/// INLINE by the precision pills it triggers, so pills appear right under their section.
struct DimensionCardView: View {
    let spec: DimensionSpec
    @Binding var answers: DimAnswers
    /// Modules the screen owns elsewhere (the catalog's fuelled/drained on the moment screen).
    var hiddenModules: Set<String> = []

    private var accent: Color { Color(hex: spec.accentHex) }
    private var score: Int? { CheckinEngine.dimensionOverall(spec.key, answers) }
    private var visible: [PillModule] { CheckinEngine.selectPills(spec, answers).filter { !hiddenModules.contains($0.key) } }
    private func after(_ anchor: String) -> [PillModule] { visible.filter { $0.after == anchor } }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(spec.title).font(FATypography.title).foregroundStyle(FAColor.ink)
                    Spacer()
                    Text(score.map(String.init) ?? "·")
                        .font(FATypography.headline)
                        .foregroundStyle(score.map { FunctionalSliderView.ramp[CheckinEngine.stateRampIndex(Double($0))] } ?? FAColor.inkMuted)
                        .monospacedDigit()
                }
                .padding(.bottom, 10)
                .accessibilityElement(children: .combine)

                if spec.hasSleepInputs {
                    SleepInputsView(specials: $answers.specials, accent: accent)
                        .padding(.bottom, 4)
                    ForEach(spec.sliders) { slider in
                        FunctionalSliderView(spec: slider, value: sliderBinding(slider.key))
                    }
                    pillBlock(after("latency") + after("wakeCount") + spec.sliders.flatMap { after($0.key) })
                } else {
                    ForEach(spec.sliders) { slider in
                        FunctionalSliderView(spec: slider, value: sliderBinding(slider.key))
                        pillBlock(after(slider.key))
                    }
                }
            }
        }
    }

    private func sliderBinding(_ key: String) -> Binding<Double?> {
        Binding(get: { answers.sliders[key] }, set: { answers.sliders[key] = $0 })
    }

    /// Recursive on purpose (a pill module can trigger further pill groups) — hence the erased type.
    private func pillBlock(_ modules: [PillModule], nested: Bool = false) -> AnyView {
        guard !modules.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                if !nested {
                    Divider().overlay(FAColor.separator).padding(.top, 6).padding(.bottom, 2)
                }
                ForEach(modules) { module in
                    PillGroupView(title: module.title, options: module.options, isOn: { (answers.pills[module.key] ?? []).contains($0) }, onToggle: { toggle(module, $0) }, accent: accent)
                    pillBlock(after(module.key), nested: true)
                }
            }
            .padding(.bottom, nested ? 0 : 8)
        )
    }

    private func toggle(_ module: PillModule, _ key: String) {
        let current = answers.pills[module.key] ?? []
        let next: [String]
        if module.single {
            next = current.contains(key) ? [] : [key]
        } else {
            next = current.contains(key) ? current.filter { $0 != key } : current + [key]
        }
        answers.pills[module.key] = next
    }
}
