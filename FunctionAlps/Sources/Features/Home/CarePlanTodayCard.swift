import SwiftUI

/// The care plan's top card on Today (mockup `iOSToday`): the programme and phase chip, "Week 7 of 16", this week's focus
/// with small checks, one nudge on an objective and one shared win. Shown when the practice has shared an active programme
/// (`member_care_plan_programmes`); until then, and whenever that read is empty or fails, Home keeps the existing
/// "My health plan" card, so nobody loses their plan to a missing share.
///
/// The practice's words only (rule 6): titles, phase names, objective and win texts are passed through; the card counts
/// weeks and checks, nothing else. This week's focus = today's actions of the habits behind a weekly-focus plan item;
/// when none is flagged, the prescribed actions due today. Supplements due now are not on the card: the member RPCs
/// carry no supplement plan yet.
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
        let habits = dependencies.habits
        let today = ISO8601.dayString(Date())
        let week = ClientCarePlanLogic.week(of: programme, today: today)
        let phase = ClientCarePlanLogic.currentPhase(programme, week: week)
        let focus: [HabitAction] = habits.plan.map {
            ClientCarePlanLogic.focusActions($0, actions: habits.actions(band: dependencies.focus.focus?.readiness?.bandValue))
        } ?? []
        let nudge = ClientCarePlanLogic.nudge(raw)
        let win = ClientCarePlanLogic.latestWin(raw)
        return FACard {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: Route.carePlan) { header(programme, week: week, phase: phase) }
                    .buttonStyle(.plain)
                if !focus.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        CPLabel(String(localized: "clientplan.focus", defaultValue: "This week's focus"))
                        ForEach(focus) { action in focusRow(action) }
                    }
                }
                if let nudge { nudgeBlock(nudge) }
                if let win { winBlock(win) }
            }
        }
    }

    private func header(_ programme: ClientProgramme, week: Int?, phase: (number: Int, of: Int, title: String?)?) -> some View {
        let title = [programme.title, phase?.title].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink).lineLimit(2)
                if let phase {
                    Text(String(localized: "clientplan.phaseOf", defaultValue: "Phase \(phase.number) of \(phase.of)"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
            Spacer(minLength: 8)
            if let week {
                Text(ClientPlanFormat.weekText(week, of: ClientCarePlanLogic.totalWeeks(of: programme)))
                    .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestDark)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(FAColor.forestSoft.opacity(0.16), in: Capsule())
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private func focusRow(_ action: HabitAction) -> some View {
        HStack(spacing: 4) {
            FACheck(done: action.done, title: action.title) {
                let habits = dependencies.habits
                Task { await habits.toggle(action) }
            }
            NavigationLink(value: Route.action(action.id)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title).font(FATypography.sans(14, .medium, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        .strikethrough(action.done, color: FAColor.inkMuted)
                        .multilineTextAlignment(.leading)
                    if action.streak >= 2 {
                        Text(String(localized: "clientplan.streak", defaultValue: "\(action.streak)-day streak"))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: FACheck.hitSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func nudgeBlock(_ nudge: ClientCarePlanLogic.Nudge) -> some View {
        NavigationLink(value: Route.clientObjective(nudge.objectiveId)) {
            VStack(alignment: .leading, spacing: 6) {
                CPLabel(String(localized: "clientplan.nudge.label", defaultValue: "Your goal"))
                Text(nudge.objectiveTitle).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text(nudge.line.label).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                    Spacer(minLength: 8)
                    Text(ClientCarePlanLogic.progressText(nudge.line)).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
                CPProgressBar(fraction: nudge.line.fraction)
                if let remaining = nudge.remaining {
                    Text(String(localized: "clientplan.nudge.toGo", defaultValue: "\(remaining) to your milestone"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FAGlassSurface(cornerRadius: FACornerRadius.sm, inset: true))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func winBlock(_ win: ClientWin) -> some View {
        NavigationLink(value: ClientCarePlanLogic.showsJourney(dependencies.clientPlan.plan ?? .empty) ? Route.carePlanJourney : Route.carePlan) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(FAColor.warning).padding(.top, 2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    CPLabel(win.achievedAt.map { String(localized: "clientplan.win.on", defaultValue: "Win · \(ClientPlanFormat.shortDate($0))") }
                            ?? String(localized: "clientplan.win", defaultValue: "Win"))
                    Text(win.text ?? "").font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
