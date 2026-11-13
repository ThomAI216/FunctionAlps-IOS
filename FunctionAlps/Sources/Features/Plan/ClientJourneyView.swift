import SwiftUI

/// "My journey" (mockup `iOSJourney`), for a member with more than one programme: the programmes as a rail — completed,
/// active now, planned — and every win the practice shared. Titles, dates and win texts are the practice's (rule 6).
struct ClientJourneyView: View {
    var body: some View {
        ClientPlanScaffold(title: String(localized: "clientplan.journey", defaultValue: "My journey")) { raw in
            let today = ISO8601.dayString(Date())
            let programmes = ClientCarePlanLogic.ordered(raw.programmes)
            if !programmes.isEmpty {
                FACard {
                    VStack(alignment: .leading, spacing: 0) {
                        CPLabel(String(localized: "clientplan.journey.programmes", defaultValue: "My programmes")).padding(.bottom, 8)
                        ForEach(Array(programmes.enumerated()), id: \.element.id) { index, programme in
                            ProgrammeRailRow(programme: programme, today: today, isFirst: index == 0, isLast: index == programmes.count - 1)
                        }
                    }
                }
            }
            if programmes.isEmpty {
                FAEmptyState(title: String(localized: "clientplan.journey.empty", defaultValue: "Your journey will appear here"),
                             message: String(localized: "clientplan.journey.emptyHint", defaultValue: "Your practitioner shares your programmes here."))
            }
        }
    }

}

private struct ProgrammeRailRow: View {
    let programme: ClientProgramme
    let today: String
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        let done = programme.status == "completed"
        let active = programme.isActive
        let week = active ? ClientCarePlanLogic.week(of: programme, today: today) : nil
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : FAColor.forestMist).frame(width: 2, height: 8)
                Image(systemName: done ? "checkmark.circle.fill" : active ? "circle.inset.filled" : "circle.dashed")
                    .font(.system(size: 18)).foregroundStyle(done || active ? FAColor.accent : FAColor.inkMuted)
                    .accessibilityHidden(true)
                Rectangle().fill(isLast ? Color.clear : FAColor.forestMist).frame(width: 2).frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(programme.title ?? "").font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    Text(statusWord).font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestDark)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(FAColor.forestSoft.opacity(done || active ? 0.16 : 0.08), in: Capsule())
                }
                if let detail { Text(detail).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary) }
                if let week, active {
                    let phase = ClientCarePlanLogic.currentPhase(programme, week: week)
                    Text([ClientPlanFormat.weekText(week, of: ClientCarePlanLogic.totalWeeks(of: programme)),
                          phase.map { String(localized: "clientplan.phaseOf", defaultValue: "Phase \($0.number) of \($0.of)") }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(FATypography.caption).foregroundStyle(FAColor.ink)
                }
            }
            .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusWord: String {
        switch programme.status {
        case "completed": String(localized: "clientplan.programme.completed", defaultValue: "Completed")
        case "active": String(localized: "clientplan.programme.active", defaultValue: "Active now")
        default: String(localized: "clientplan.programme.planned", defaultValue: "Planned")
        }
    }

    /// "Jan 2026 · 16 weeks", from the dates the practice set; nil when it set none.
    private var detail: String? {
        var parts: [String] = []
        if let start = programme.startDate, !start.isEmpty {
            if let end = programme.endDate, !end.isEmpty {
                parts.append("\(ClientPlanFormat.monthYear(start)) – \(ClientPlanFormat.monthYear(end))")
            } else {
                parts.append(programme.status == "planned"
                    ? String(localized: "clientplan.programme.startsAround", defaultValue: "Expected to start around \(ClientPlanFormat.monthYear(start))")
                    : ClientPlanFormat.monthYear(start))
            }
        }
        if let weeks = programme.plannedWeeks, weeks > 0 {
            parts.append(String(localized: "clientplan.programme.weeks", defaultValue: "\(weeks) weeks"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
