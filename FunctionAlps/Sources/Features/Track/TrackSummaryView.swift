import SwiftUI

/// "Your first week" on the Foundation card — there from the day a practitioner approved the day-7 summary.
struct TrackSummaryRow: View {
    var body: some View {
        NavigationLink(value: Route.trackSummary) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 16, weight: .semibold)).foregroundStyle(FAColor.forest)
                    .frame(width: 40, height: 40)
                    .background(FAColor.forestSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "track.summary.title", defaultValue: "Your first week"))
                        .font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    Text(String(localized: "track.summary.row", defaultValue: "Your week-1 summary is ready"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .modifier(FAGlassSurface(cornerRadius: 16, inset: true))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The member's approved day-7 summary (`track_summary.content` v1), laid out as written: what we learned, the
/// goals, the actions new in week two, and the energy and protein ranges. Every word is the practice's, approved
/// by a practitioner before the member could read it (rule 6); `provenance` and `ai_derived` are never shown.
///
/// States (rule 5): reading → loading; failed → error with retry; no approved row (or a content version this
/// build does not read) → "not ready yet"; signed out → the service hands over to `AuthService`.
struct TrackSummaryView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let track = dependencies.track
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "track.summary.title", defaultValue: "Your first week"), hairline: true)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let summary = track.summary {
                        TrackSummaryBody(content: summary.content)
                    } else {
                        switch track.summaryPhase {
                        case .idle, .loading:
                            FALoadingState().frame(minHeight: 240)
                        case .failed(let message):
                            FACard {
                                FAErrorState(title: String(localized: "track.summary.error", defaultValue: "Couldn't load your summary"), message: message) {
                                    Task { await track.loadSummary() }
                                }
                            }
                        case .loaded:
                            FACard {
                                FAEmptyState(title: String(localized: "track.summary.empty.title", defaultValue: "Your summary isn't ready yet"),
                                             message: String(localized: "track.summary.empty.message", defaultValue: "It appears here once your practitioner has reviewed it."),
                                             systemImage: "doc.text")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await track.loadSummary() }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if track.summary == nil { await track.loadSummary() }
        }
    }
}

private struct TrackSummaryBody: View {
    let content: TrackSummaryContent

    var body: some View {
        if !content.learned.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 14) {
                    heading(String(localized: "track.summary.learned", defaultValue: "What we learned"))
                    ForEach(content.learned) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sectionTitle(section.key)).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                .accessibilityAddTraits(.isHeader)
                            Text(section.text).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink2).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        if !content.goals.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    heading(String(localized: "track.summary.goals", defaultValue: "Your goals"))
                    ForEach(content.goals) { goal in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "target").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                                .accessibilityHidden(true)
                            Text(goal.label).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        if !content.weekTwoActions.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 12) {
                    heading(String(localized: "track.summary.weekTwo", defaultValue: "Your week-2 actions"))
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "track.questionnaire.day", defaultValue: "Day \(day)").uppercased())
                                .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(content.weekTwoActions.filter { $0.day == day }) { action in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(action.title).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    if let moment = action.moment {
                                        Text(momentLabel(moment)).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if content.energyKcal != nil || content.proteinG != nil {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    heading(String(localized: "track.summary.ranges", defaultValue: "Your daily ranges"))
                    if let r = content.energyKcal, let kcal = TrackLogic.range(r.low, r.high) {
                        Label(String(localized: "track.range.kcal", defaultValue: "~\(kcal.0)–\(kcal.1) kcal"), systemImage: "flame")
                            .font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    }
                    if let r = content.proteinG, let protein = TrackLogic.range(r.low, r.high) {
                        Label(String(localized: "track.range.protein", defaultValue: "~\(protein.0)–\(protein.1) g protein"), systemImage: "fork.knife")
                            .font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    }
                }
            }
        }
    }

    private var days: [Int] { Array(Set(content.weekTwoActions.map(\.day))).sorted() }

    private func heading(_ text: String) -> some View {
        Text(text).font(FATypography.display(19, relativeTo: .title3)).foregroundStyle(FAColor.ink)
            .accessibilityAddTraits(.isHeader)
    }

    /// CLINICAL's section titles (`SECTION_TITLES`), in the app's language.
    private func sectionTitle(_ key: String) -> String {
        switch key {
        case "context": String(localized: "track.summary.section.context", defaultValue: "Your context")
        case "food": String(localized: "track.summary.section.food", defaultValue: "Nutrition")
        case "movement": String(localized: "track.summary.section.movement", defaultValue: "Movement")
        case "sleep": String(localized: "track.summary.section.sleep", defaultValue: "Sleep")
        case "stress": String(localized: "track.summary.section.stress", defaultValue: "Mental and emotional health")
        default: key
        }
    }

    private func momentLabel(_ moment: TrackMoment) -> String {
        switch moment {
        case .morning: HabitSlot.morning.label
        case .midday: HabitSlot.midday.label
        case .evening: HabitSlot.evening.label
        case .day: String(localized: "track.moment.day", defaultValue: "During the day")
        }
    }
}
