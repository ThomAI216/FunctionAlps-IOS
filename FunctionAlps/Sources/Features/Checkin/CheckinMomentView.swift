import SwiftUI

/// ONE screen per check-in moment. TWO are asked for: the MORNING (last night, and what today is for)
/// and the EVENING (the day you lived — energy, focus, mood, calm, and the whole digestion read).
/// Nothing is hidden behind an expander: what a moment asks, it asks on one page.
struct CheckinMomentView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let slot: MomentSlot
    @State private var model: CheckinMomentViewModel?

    var body: some View {
        ZStack {
            if let model {
                CheckinMomentScreen(model: model) {
                    // Saved: today's reminder for this moment is no longer needed; first save is the moment to ask for permission.
                    let notifications = dependencies.notifications
                    notifications.momentDone(slot, day: dependencies.checkins.today)
                    Task { await notifications.askIfNeeded() }
                    if slot == .morning {
                        let focus = dependencies.focus
                        Task { await focus.load(recompute: true) }
                    }
                    dismiss()
                }
            }
        }
        .faWall()
        .navigationTitle(slot.localizedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = CheckinMomentViewModel(slot: slot, checkins: dependencies.checkins, members: dependencies.members, auth: dependencies.auth,
                                               gut: dependencies.gut, wearables: dependencies.wearables)
                model = m
                await m.prefill()
            }
        }
    }
}

private struct CheckinMomentScreen: View {
    @Bindable var model: CheckinMomentViewModel
    let onSaved: () -> Void

    /// The catalog owns these on this screen — the ENERGY spec's same-named twins are hidden so
    /// nobody is asked the same question twice.
    private let catalogOwned: Set<String> = ["fuelled", "drained", "day_intent", "day_priority"]

    /// The evening cannot save before its digestion has loaded, or a blank answer set would sit on
    /// top of what was already written today.
    private var canSave: Bool { model.gut.map(\.loaded) ?? true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                VStack(alignment: .leading, spacing: FASpacing.xs) {
                    Text(model.greeting).font(FATypography.largeTitle).foregroundStyle(FAColor.ink)
                    Text(model.intro).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                }
                .padding(.top, FASpacing.sm)

                ForEach(model.sections, id: \.self) { s in section(s) }

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

                FAButton(title: model.isSaving ? String(localized: "action.saving", defaultValue: "Saving…") : String(localized: "action.save", defaultValue: "Save"),
                         isLoading: model.isSaving, isEnabled: canSave) {
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
            if let note = model.sleepFromWearableNote, let source = model.sleepFromWearable {
                HStack(spacing: 6) {
                    Image(systemName: WearableVendor.sourceSymbol(source.sourceId))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WearableVendor.sourceTint(source.sourceId))
                    Text(note).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 6)
            }
        case .intent:
            catalogCard([CatalogSection(group: .dayIntent, title: String(localized: "checkin.intent", defaultValue: "How are you walking into the day?"), accent: Color(hex: 0x6366F1))])
        case .priority:
            sectionLabel(String(localized: "checkin.today", defaultValue: "Today"))
            catalogCard([CatalogSection(group: .dayPriority, title: String(localized: "checkin.priority", defaultValue: "What is today for?"), accent: FAColor.forestSoft)])
        case .markers:
            sectionLabel(model.markersTitle)
            DimensionCardView(spec: FunctionalSchema.energy, answers: dimBinding(.energy), hiddenModules: catalogOwned)
            DimensionCardView(spec: FunctionalSchema.mood, answers: dimBinding(.mood))
            DimensionCardView(spec: FunctionalSchema.stress, answers: dimBinding(.stress))
        case .digestion:
            if let gut = model.gut {
                sectionLabel(String(localized: "checkin.digestion", defaultValue: "Your digestion today"))
                DigestionSections(model: gut)
            }
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

/// The gut check-in, inside the evening reflection: comfort, stool and food reactions, the red flags,
/// and the one note that travels with both the moment and the day's digestion detail.
private struct DigestionSections: View {
    @Bindable var model: GutCheckinViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: FASpacing.md) {
            ForEach(GutSchema.dimensions) { spec in
                GutDimensionCard(spec: spec, answers: binding(spec.key), ratedMeals: spec.key == .reactions ? model.ratedMeals : [])
            }
            GutRedFlagsCard(flags: $model.redFlags)
            noteBlock
        }
    }

    private func binding(_ key: GutDimKey) -> Binding<GutAnswers> {
        Binding(get: { model.answers[key] ?? .empty }, set: { model.answers[key] = $0 })
    }

    @ViewBuilder
    private var noteBlock: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { model.notesOpen.toggle() } } label: {
            HStack {
                Text(model.notesOpen ? String(localized: "gut.notes.hide", defaultValue: "Hide note") : String(localized: "checkin.note.add", defaultValue: "Add a note about your day (optional)"))
                    .font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.inkSecondary)
                Spacer()
                Text(model.notesOpen ? "−" : "+").font(.system(size: 18, weight: .medium)).foregroundStyle(FAColor.inkSecondary)
            }
            .padding(.vertical, 13).padding(.horizontal, 18)
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        if model.notesOpen {
            TextField(String(localized: "checkin.note.placeholder", defaultValue: "Anything worth remembering about today — meals, symptoms, stress, timing."), text: $model.notes, axis: .vertical)
                .lineLimit(4...8)
                .font(FATypography.sans(14.5, relativeTo: .body)).foregroundStyle(FAColor.ink)
                .padding(14)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1))
        }
    }
}
