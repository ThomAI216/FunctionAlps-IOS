import SwiftUI

/// One objective (mockup `iOSObjective`): the member's own words, what it means (the practice's statement), and each
/// milestone with its progress and date. Only what the practice returned is shown (rule 6) — a section with nothing
/// behind it is left out, never filled in.
struct ClientObjectiveView: View {
    let objectiveId: String

    var body: some View {
        ClientPlanScaffold(title: String(localized: "clientplan.objective.title", defaultValue: "Goal")) { raw in
            if let objective = raw.objectives.first(where: { $0.id == objectiveId }) {
                content(objective, in: raw)
            } else {
                FAEmptyState(title: String(localized: "clientplan.objective.gone", defaultValue: "This goal is no longer in your plan"),
                             message: String(localized: "clientplan.objective.goneHint", defaultValue: "Go back to your plan to see what is current."))
            }
        }
    }

    @ViewBuilder
    private func content(_ objective: ClientObjective, in raw: ClientCarePlanRaw) -> some View {
        let all = ClientCarePlanLogic.objectives(raw)
        let index = all.firstIndex { $0.id == objective.id }
        let own = ClientCarePlanLogic.usesOwnWords(objective)
        let statement = objective.statement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lines = ClientCarePlanLogic.lines(objective)
        let met = ClientCarePlanLogic.milestones(objective)

        if let index, all.count > 1 {
            Text(String(localized: "clientplan.objective.index", defaultValue: "Goal \(index + 1) of \(all.count)"))
                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
        }

        FACard {
            VStack(alignment: .leading, spacing: 10) {
                CPLabel(own ? String(localized: "clientplan.objective.inMyWords", defaultValue: "In my words")
                            : String(localized: "clientplan.objective.goal", defaultValue: "Goal"))
                let title = ClientCarePlanLogic.title(objective)
                Text(own ? "“\(title)”" : title)
                    .font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if objective.status == "achieved" {
                    Label(String(localized: "clientplan.achieved", defaultValue: "Achieved"), systemImage: "checkmark.circle.fill")
                        .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestDark)
                }
            }
        }

        if own, !statement.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    CPLabel(String(localized: "clientplan.objective.means", defaultValue: "What it means for me"))
                    Text(statement).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if !lines.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CPLabel(String(localized: "clientplan.objective.milestones", defaultValue: "Milestones"))
                        Spacer(minLength: 8)
                        Text(String(localized: "clientplan.objective.milestoneCount", defaultValue: "\(met.met) of \(met.total) reached"))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                if line.met {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(FAColor.accent)
                                        .accessibilityHidden(true)
                                }
                                Text(line.label).font(FATypography.sans(14, .medium, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                Spacer(minLength: 8)
                                Text(ClientCarePlanLogic.progressText(line)).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            }
                            CPProgressBar(fraction: line.fraction, height: 6)
                            if let due = line.dueDate, !line.met {
                                Text(String(localized: "clientplan.objective.due", defaultValue: "Check \(ClientPlanFormat.shortDate(due))"))
                                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        } else if let progress = ClientCarePlanLogic.progress(objective) {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    CPLabel(String(localized: "clientplan.objective.progress", defaultValue: "Progress"))
                    CPProgressBar(fraction: progress, height: 6)
                    Text("\(Int((progress * 100).rounded()))%").font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }

        if let target = objective.targetDate, objective.status != "achieved" {
            Text(String(localized: "clientplan.objective.target", defaultValue: "Target \(ClientPlanFormat.shortDate(target))"))
                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
        }
    }
}
