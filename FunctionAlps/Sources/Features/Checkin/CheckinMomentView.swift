import SwiftUI

/// ONE screen for every check-in moment — morning / midday / evening.
/// Morning is short by default (last night + how you're walking into the day); the functional
/// markers and fuelled/drained sit behind one warm expander. Later moments show everything.
struct CheckinMomentView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let slot: MomentSlot
    @State private var model: CheckinMomentViewModel?

    var body: some View {
        ZStack {
            if let model {
                CheckinMomentScreen(model: model) { dismiss() }
            }
        }
        .faWall()
        .navigationTitle(slot.localizedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = CheckinMomentViewModel(slot: slot, checkins: dependencies.checkins, members: dependencies.members, auth: dependencies.auth)
                model = m
                await m.prefill()
            }
        }
    }
}

private struct CheckinMomentScreen: View {
    @Bindable var model: CheckinMomentViewModel
    let onSaved: () -> Void

    /// The catalog owns fuelled/drained on this screen — the ENERGY spec's twins are hidden.
    private let catalogOwned: Set<String> = ["fuelled", "drained", "day_intent"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                VStack(alignment: .leading, spacing: FASpacing.xs) {
                    Text(model.greeting).font(FATypography.largeTitle).foregroundStyle(FAColor.ink)
                    Text(model.intro).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                }
                .padding(.top, FASpacing.sm)

                ForEach(model.coreSections, id: \.self) { s in section(s) }

                if !model.moreSections.isEmpty {
                    if model.showMore {
                        ForEach(model.moreSections, id: \.self) { s in section(s) }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        Button { withAnimation(.easeOut(duration: 0.26)) { model.showMore = true } } label: {
                            FACard {
                                HStack(spacing: FASpacing.md) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(String(localized: "checkin.more.title", defaultValue: "Tell us a bit more"))
                                            .font(FATypography.headline).foregroundStyle(FAColor.ink)
                                        Text(String(localized: "checkin.more.sub", defaultValue: "Energy, mood and calm · about a minute."))
                                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.down").foregroundStyle(FAColor.inkSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = model.saveError {
                    FACard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "checkin.saveFailed", defaultValue: "Couldn't save this moment"))
                                .font(FATypography.headline).foregroundStyle(FAColor.danger)
                            Text(String(localized: "checkin.saveFailed.hint", defaultValue: "Your answers are still here · tap Save to try again."))
                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            if BuildInfo.showsTechnicalDetails {
                                Text(error).font(FATypography.caption).foregroundStyle(FAColor.inkMuted)
                            }
                        }
                    }
                }

                FAButton(title: model.isSaving ? String(localized: "action.saving", defaultValue: "Saving…") : String(localized: "action.save", defaultValue: "Save"), isLoading: model.isSaving) {
                    Task { if await model.save() { onSaved() } }
                }
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func section(_ section: CheckinMomentViewModel.Section) -> some View {
        switch section {
        case .sleep:
            sectionLabel(String(localized: "checkin.lastNight", defaultValue: "Last night"))
            DimensionCardView(spec: FunctionalSchema.sleep, answers: dimBinding(.sleep))
        case .intent:
            catalogCard([CatalogSection(group: .dayIntent, title: String(localized: "checkin.intent", defaultValue: "How are you walking into the day?"), accent: Color(hex: 0x6366F1))])
        case .markers:
            sectionLabel(model.markersTitle)
            DimensionCardView(spec: FunctionalSchema.energy, answers: dimBinding(.energy), hiddenModules: catalogOwned)
            DimensionCardView(spec: FunctionalSchema.mood, answers: dimBinding(.mood))
            DimensionCardView(spec: FunctionalSchema.stress, answers: dimBinding(.stress))
        case .context:
            catalogCard([
                CatalogSection(group: .fuelled, title: String(localized: "pills.fuelled", defaultValue: "What fuelled you?"), accent: FAColor.forestSoft),
                CatalogSection(group: .drained, title: String(localized: "pills.drained", defaultValue: "What drained you?"), accent: Color(hex: 0xD97706)),
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
