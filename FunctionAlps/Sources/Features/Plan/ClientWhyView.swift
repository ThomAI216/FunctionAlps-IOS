import SwiftUI

/// "Why we're doing this": the hypotheses the practice chose to share, in plain words — what it is, how we know,
/// and the reading behind it. Each one opens in place. Nothing reaches this screen without a clinician's share
/// (CLINICAL 325): a hypothesis not shared, or dismissed since, is not here.
struct ClientWhyView: View {
    var body: some View {
        ClientPlanScaffold(title: String(localized: "clientplan.why", defaultValue: "Why we're doing this")) { raw in
            if raw.hypotheses.isEmpty {
                FAEmptyState(title: String(localized: "clientplan.why.empty", defaultValue: "Nothing shared here yet"),
                             message: String(localized: "clientplan.why.emptyHint", defaultValue: "Your practitioner will explain the reasoning behind your plan here."))
            } else {
                ForEach(raw.hypotheses) { HypothesisCard(hypothesis: $0) }
            }
        }
    }
}

private struct HypothesisCard: View {
    let hypothesis: ClientHypothesis
    @State private var open = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let title = hypothesis.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let explanation = hypothesis.explanation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let how = hypothesis.howWeKnow?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let links = ClientResource.readable(hypothesis.resources)
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title).font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FAColor.inkMuted).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(open ? String(localized: "clientplan.collapse", defaultValue: "Collapse")
                                        : String(localized: "clientplan.expand", defaultValue: "Expand"))
                if open {
                    if !explanation.isEmpty {
                        Text(explanation).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !how.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            CPLabel(String(localized: "clientplan.why.howWeKnow", defaultValue: "How we know"))
                            Text(how).font(FATypography.sans(14, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !links.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            CPLabel(String(localized: "clientplan.why.read", defaultValue: "To read"))
                            ForEach(Array(links.enumerated()), id: \.offset) { _, resource in
                                if let url = resource.link {
                                    Button { openURL(url) } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.up.right.square").font(.system(size: 12)).accessibilityHidden(true)
                                            Text(resource.displayTitle).font(FATypography.sans(14, .medium, relativeTo: .subheadline)).multilineTextAlignment(.leading)
                                            Spacer(minLength: 0)
                                        }
                                        .foregroundStyle(FAColor.forest)
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(resource.displayTitle).font(FATypography.sans(14, .medium, relativeTo: .subheadline))
                                        .foregroundStyle(FAColor.ink).multilineTextAlignment(.leading)
                                        .frame(minHeight: 44, alignment: .leading)
                                }
                            }
                        }
                    }
                    if let name = hypothesis.proposedByFirstName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                        Text(String(localized: "clientplan.why.by", defaultValue: "From \(name)"))
                            .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    }
                }
            }
        }
    }
}
