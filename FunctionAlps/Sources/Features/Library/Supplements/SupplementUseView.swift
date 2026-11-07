import SwiftUI

/// One use of a supplement (mockup phones 4–5): evidence first, in words and a bar; benefits to look for; best
/// form, how much, when, how long; the label; "Ask us first if"; "Goes with"; sources. A weak or not-supported
/// use carries no dose and no how-to — flagged plainly instead.
struct SupplementUseView: View {
    let use: SupplementUse
    let entry: SupplementEntry
    let onSource: (SourceKey) -> Void
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group { top }
            Group { bottom }
        }
    }

    @ViewBuilder
    private var top: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(use.supplement.name) · \(SupplementLogic.useChip(title: use.title, supplement: use.supplement.name))".uppercased())
                .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FAColor.forestSoft)
            Text(use.title).font(FATypography.display(25, relativeTo: .title)).foregroundStyle(FAColor.ink)
        }
        .padding(.top, 4)
        EvidenceCard(evidence: use.evidence, sources: use.sources, onSource: onSource)
        if !use.benefits.isEmpty {
            SupplementSection(title: String(localized: "supplement.benefits", defaultValue: "Benefits to look for")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(use.benefits.enumerated()), id: \.offset) { _, item in
                        SupplementItemRow(item: item, style: .check, sources: use.sources, onSource: onSource)
                    }
                }
            }
        }
        if SupplementLogic.carriesDose(use.evidence.level) {
            if !use.forms.isEmpty || use.dose != nil || use.timing != nil || use.onset != nil {
                SupplementSection(title: String(localized: "supplement.howTo", defaultValue: "How to take it")) {
                    SupplementKeyValues(rows: [
                        (String(localized: "supplement.howTo.form", defaultValue: "Best form"), use.forms),
                        (String(localized: "supplement.howTo.dose", defaultValue: "How much"), use.dose.map { [$0] } ?? []),
                        (String(localized: "supplement.howTo.timing", defaultValue: "When"), use.timing.map { [$0] } ?? []),
                        (String(localized: "supplement.howTo.onset", defaultValue: "How long"), use.onset.map { [$0] } ?? []),
                    ], sources: use.sources, onSource: onSource)
                }
            }
        } else {
            // Chrome only; the reason is the publisher's evidence line (rule 6: no health wording written here).
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "supplement.noDose", defaultValue: "No dose on this page."))
                    .font(FATypography.sans(11.5, .bold, relativeTo: .footnote)).foregroundStyle(Color(hex: 0x4B2A2F))
                if let line = use.evidence.line, !line.isEmpty {
                    Text(line).font(FATypography.sans(11.5, relativeTo: .footnote)).foregroundStyle(Color(hex: 0x4B2A2F))
                }
            }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x9F2D3A, opacity: 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: 0x9F2D3A, opacity: 0.2), lineWidth: 1) }
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if !use.label.isEmpty {
            SupplementSection(title: String(localized: "supplement.label", defaultValue: "On the label")) { items(use.label) }
        }
        if !use.askFirst.isEmpty {
            SupplementSection(title: String(localized: "supplement.askFirst", defaultValue: "Ask us first if"), warn: true) {
                items(use.askFirst)
                Button { router.push(.supplement(use.supplement.slug)) } label: {
                    Text(String(localized: "supplement.fullList", defaultValue: "See the full list ›"))
                        .font(FATypography.sans(11, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "supplement.fullList.a11y", defaultValue: "Open the \(use.supplement.name) page"))
            }
        }
        GoesWithCard(habitIds: use.habits)
        SupplementArticles(articles: SupplementLogic.articles(use.articles, in: entry.bundle))
        SupplementSourcesCard(sources: use.sources) { if let first = use.sources.first { onSource(first.n) } }
        Button { router.push(.supplement(use.supplement.slug)) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                Text(String(localized: "supplement.backToPage", defaultValue: "All about \(use.supplement.name)"))
                    .font(FATypography.sans(12, .semibold, relativeTo: .caption))
            }
            .foregroundStyle(FAColor.forest)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .faFrost(cornerRadius: 14, horizontal: 14, vertical: 2)
        }
        .buttonStyle(.plain)
    }

    private func items(_ list: [SupplementItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, item in
                SupplementItemRow(item: item, style: .bullet, sources: use.sources, onSource: onSource)
            }
        }
    }
}
