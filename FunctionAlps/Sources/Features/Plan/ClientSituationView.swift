import SwiftUI

/// "Your situation & evolution" (Thomas, 2026-11-12: "our proof of work"): where the client started, then ONE line per
/// complaint — a status (Managed / Being taken care of / Not yet managed), the practice's one-line summary and a small
/// curve from the check-in days the app already holds. A line opens to what changed and what helped (validated and
/// shared by a clinician, never automatic). Words are the practice's (rule 6); the curve is only drawn for a signal the
/// daily check-in actually holds.
struct ClientSituationView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ClientPlanScaffold(title: String(localized: "clientplan.situation", defaultValue: "Your situation & evolution")) { raw in
            let started = raw.situation.filter { !($0.situationText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
            if started.isEmpty && raw.complaints.isEmpty {
                FAEmptyState(title: String(localized: "clientplan.situation.empty", defaultValue: "Nothing shared here yet"),
                             message: String(localized: "clientplan.situation.emptyHint", defaultValue: "Your practitioner will share where you started and how it is changing."))
            } else {
                if !started.isEmpty { startedCard(started, programmes: raw.programmes) }
                if !raw.complaints.isEmpty { complaintsCard(raw) }
            }
        }
    }

    private func startedCard(_ rows: [ClientSituation], programmes: [ClientProgramme]) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                CPLabel(String(localized: "clientplan.situation.started", defaultValue: "Where you started"))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 4) {
                        if rows.count > 1, let title = row.title, !title.isEmpty {
                            Text(title).font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.forestDark)
                        }
                        Text(row.situationText ?? "").font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let start = row.startDate {
                            Text(String(localized: "clientplan.situation.since", defaultValue: "Since \(ClientPlanFormat.monthYear(start))"))
                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        }
                    }
                }
            }
        }
    }

    private func complaintsCard(_ raw: ClientCarePlanRaw) -> some View {
        let history = dependencies.clientPlan.history
        return FACard {
            VStack(alignment: .leading, spacing: 0) {
                CPLabel(String(localized: "clientplan.situation.complaints", defaultValue: "Your complaints and symptoms")).padding(.bottom, 6)
                ForEach(raw.complaints) { complaint in
                    ComplaintRow(
                        complaint: complaint,
                        evolution: ClientCarePlanLogic.evolution(for: complaint, in: raw),
                        curve: ClientCarePlanLogic.series(signalKey: complaint.signalKey, label: complaint.complaintLabel, history: history))
                    if complaint.id != raw.complaints.last?.id { Divider() }
                }
            }
        }
    }
}

/// One complaint: collapsed = name, status, one-line summary and the mini curve; open = what changed and what helped.
private struct ComplaintRow: View {
    let complaint: ClientComplaint
    let evolution: [ClientEvolution]
    let curve: [Double]
    @State private var open = false

    var body: some View {
        let status = ClientCarePlanLogic.ComplaintStatus(complaint.status)
        let summary = complaint.clientSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(ClientCarePlanLogic.name(complaint)).font(FATypography.sans(15, .semibold, relativeTo: .headline))
                                .foregroundStyle(FAColor.ink).multilineTextAlignment(.leading)
                            CPStatusPill(status: status)
                        }
                        if !summary.isEmpty {
                            Text(summary).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.inkSecondary)
                                .lineLimit(open ? nil : 2).multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    if !curve.isEmpty { MiniCurve(values: curve) }
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FAColor.inkMuted).padding(.top, 4).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? String(localized: "clientplan.collapse", defaultValue: "Collapse")
                                    : String(localized: "clientplan.expand", defaultValue: "Expand"))
            if open {
                if evolution.isEmpty {
                    Text(String(localized: "clientplan.situation.noEvolution", defaultValue: "Nothing more to show here yet."))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                } else {
                    ForEach(evolution) { EvolutionBlock(entry: $0) }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// What changed (direction, before → after, the practice's sentence) and what helped (the cause), for one validated link.
private struct EvolutionBlock: View {
    let entry: ClientEvolution

    var body: some View {
        let text = entry.clientText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cause = entry.causeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(String(localized: "careplan.direction.improved", defaultValue: "Improved")).font(FATypography.sans(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(FAColor.forestDark)
                if let change = ClientCarePlanLogic.beforeAfter(entry) {
                    Text(change).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
            if !text.isEmpty {
                Text(text).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
            }
            if !cause.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    CPLabel(String(localized: "clientplan.situation.whatHelped", defaultValue: "What helped"))
                    Text("\(ClientCarePlanLogic.causeKindLabel(entry.causeKind)) · \(cause)")
                        .font(FATypography.sans(13, .medium, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FAColor.forestGlow.opacity(0.7), in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
