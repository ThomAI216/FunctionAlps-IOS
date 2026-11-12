import SwiftUI

/// The cards of a check-in screen, in the order its view model asks them. Shared by the daily check-in, the morning's
/// "Reveal the rest of the day" and the caught-up "Yesterday": one place draws a day's questions, so they can never drift.
/// ("Feeling for the day" is the morning's own card — `MorningCheckinView` draws it, not this view.)
struct CheckinSectionsView: View {
    @Bindable var model: CheckinMomentViewModel

    /// The catalog owns these on this screen — the ENERGY spec's same-named twins are hidden so
    /// nobody is asked the same question twice.
    private let catalogOwned: Set<String> = ["fuelled", "drained", "day_intent", "day_priority"]

    var body: some View {
        ForEach(model.sections, id: \.self) { s in section(s) }
    }

    @ViewBuilder
    private func section(_ section: CheckinMomentViewModel.Section) -> some View {
        switch section {
        case .sleep:
            sectionLabel(String(localized: "checkin.lastNight", defaultValue: "Last night"))
            DimensionCardView(spec: FunctionalSchema.sleep, answers: dimBinding(.sleep), recordedNight: model.recordedNight, lookingForNight: model.syncingNight)
        case .dayFeeling:
            // Drawn by the morning screen (it owns the card's data); nothing here.
            EmptyView()
        case .markers:
            sectionLabel(model.markersTitle)
            DimensionCardView(spec: FunctionalSchema.energy, answers: dimBinding(.energy), hiddenModules: catalogOwned)
                .id("showcase.energy")
            DimensionCardView(spec: FunctionalSchema.mood, answers: dimBinding(.mood))
                .id("showcase.mood")
            DimensionCardView(spec: FunctionalSchema.stress, answers: dimBinding(.stress))
        case .digestion:
            if let gut = model.gut {
                sectionLabel(String(localized: "checkin.digestion", defaultValue: "Your digestion today"))
                DigestionSections(model: gut)
            }
        case .context:
            catalogCard([
                CatalogSection(group: .fuelled, title: String(localized: "pills.fuelled", defaultValue: "What fuelled you?"), accent: FAColor.forestSoft),
                CatalogSection(group: .drained, title: String(localized: "pills.drained", defaultValue: "What drained you?"), accent: Color(hex: 0xC2410C)),
            ])
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(FATypography.label)
            .foregroundStyle(FAColor.inkSecondary)
            .tracking(0.4)
            .padding(.top, 6)
    }

    private struct CatalogSection: Identifiable {
        let group: PillGroup
        let title: String
        let accent: Color
        var id: PillGroup { group }
    }

    private func catalogCard(_ sections: [CatalogSection]) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    PillGroupView(
                        title: section.title,
                        options: PillCatalog.pills(for: section.group, slot: model.slot).map { PillOption(key: $0.key, label: $0.label) },
                        isOn: { model.isCatalogOn(section.group, $0) },
                        onToggle: { model.toggleCatalog(section.group, $0) },
                        accent: section.accent
                    )
                }
            }
            .padding(.top, -12)
        }
    }

    private func dimBinding(_ key: DimKey) -> Binding<DimAnswers> {
        Binding(get: { model.answers[key] ?? .empty }, set: { model.answers[key] = $0 })
    }
}

