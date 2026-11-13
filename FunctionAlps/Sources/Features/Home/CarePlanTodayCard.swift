import SwiftUI

/// The care plan's top card on Home (mockup `iOSHome`, decisions 2026-11-12). It replaces the old Home plan card and shows
/// only the plan: the programme name, a phase bar (done, current, to do), "week X of Y", and the objectives in the client's
/// own words with no numbers (the numbers are on My Plan). Tapping it opens My Plan.
///
/// Shown when the practice has shared an active programme; until then, and whenever that read is empty or fails, Home
/// keeps the existing "My health plan" card, so nobody loses their plan to a missing share.
struct CarePlanTodayCard: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let service = dependencies.clientPlan
        Group {
            if case .loaded(let raw) = service.state, let programme = ClientCarePlanLogic.leadProgramme(raw) {
                card(raw, programme)
            } else {
                HealthPlanCard()
            }
        }
        .task { await service.load() }
    }

    private func card(_ raw: ClientCarePlanRaw, _ programme: ClientProgramme) -> some View {
        let today = ISO8601.dayString(Date())
        let week = ClientCarePlanLogic.week(of: programme, today: today)
        let steps = ClientCarePlanLogic.phaseSteps(programme, week: week)
        let objectives = ClientCarePlanLogic.objectives(raw, programmeId: programme.id)
        return NavigationLink(value: Route.carePlan) {
            TintedFACard(tint: PlanScreensLogic.bandHex(kind: programme.kind)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(programme.title ?? "")
                            .font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let week {
                            Text(ClientPlanFormat.weekText(week, of: ClientCarePlanLogic.totalWeeks(of: programme)))
                                .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestDark)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(FAColor.forestSoft.opacity(0.16), in: Capsule())
                        }
                    }
                    if !steps.isEmpty { PhaseBar(steps: steps, showsYouAreHere: false) }
                    if !objectives.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(objectives) { objective in
                                Text("“\(ClientCarePlanLogic.title(objective))”")
                                    .font(FATypography.display(16, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
