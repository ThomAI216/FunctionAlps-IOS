import SwiftUI

/// A supplement page (mockup phones 2–3): the visual and the one line, benefits to look for, what it does in the
/// body, the uses as tappable tracks ranked by evidence, the label, "Ask us first if", side effects and the upper
/// limit, food first, "Goes with", the articles, the sources. Every sentence is the payload's.
struct SupplementPageView: View {
    let page: SupplementPage
    let entry: SupplementEntry
    let onSource: (SourceKey) -> Void
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                top
                middle
            }
            Group {
                bottom
            }
        }
    }

    @ViewBuilder
    private var top: some View {
        hero
        if let line = page.line, !line.isEmpty {
            Text(line).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(Color(hex: 0x33332C))
                .fixedSize(horizontal: false, vertical: true)
        }
        if !page.benefits.isEmpty {
            SupplementSection(title: String(localized: "supplement.benefits", defaultValue: "Benefits to look for")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(page.benefits.enumerated()), id: \.offset) { _, item in
                        SupplementItemRow(item: item, style: .check, tag: chip(for: item.use), sources: page.sources, onSource: onSource)
                    }
                }
            }
        }
        if !page.physiology.isEmpty {
            SupplementSection(title: String(localized: "supplement.physiology", defaultValue: "What it does in your body")) {
                SupplementKeyValues(rows: [
                    (String(localized: "supplement.physiology.role", defaultValue: "Its job"), page.physiology.role),
                    (String(localized: "supplement.physiology.stored", defaultValue: "Stored"), page.physiology.stored),
                    (String(localized: "supplement.physiology.absorbed", defaultValue: "Absorbed"), page.physiology.absorbed),
                    (String(localized: "supplement.physiology.loweredBy", defaultValue: "Lowered by"), page.physiology.loweredBy),
                ], sources: page.sources, onSource: onSource)
            }
        }
    }

    @ViewBuilder
    private var middle: some View {
        if !page.uses.isEmpty {
            SupplementSection(title: String(localized: "supplement.uses", defaultValue: "What it's used for"),
                              note: String(localized: "supplement.uses.note", defaultValue: "tap one")) {
                VStack(spacing: 6) {
                    ForEach(SupplementLogic.ordered(page.uses)) { use in useRow(use) }
                }
            }
        }
        if !page.label.isEmpty {
            SupplementSection(title: String(localized: "supplement.label", defaultValue: "On the label")) {
                items(page.label)
            }
        }
        if !page.askFirst.isEmpty {
            SupplementSection(title: String(localized: "supplement.askFirst", defaultValue: "Ask us first if"), warn: true) {
                items(page.askFirst)
            }
        }
        if !page.sideEffects.isEmpty || !page.upperLimits.isEmpty {
            SupplementSection(title: String(localized: "supplement.goodToKnow", defaultValue: "Good to know")) {
                SupplementKeyValues(rows: [
                    (String(localized: "supplement.sideEffects", defaultValue: "Side effects"), page.sideEffects),
                    (String(localized: "supplement.upperLimit", defaultValue: "Upper limit"), page.upperLimits),
                ], sources: page.sources, onSource: onSource)
            }
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if !page.food.isEmpty {
            SupplementSection(title: String(localized: "supplement.food", defaultValue: "Food first"),
                              note: String(localized: "supplement.food.note", defaultValue: "per portion")) {
                FlowLayout(spacing: 5) {
                    ForEach(page.food) { food in foodChip(food) }
                }
            }
        }
        GoesWithCard(habitIds: page.habits)
        SupplementArticles(articles: SupplementLogic.articles(page.articles, in: entry.bundle))
        SupplementSourcesCard(sources: page.sources) { if let first = page.sources.first { onSource(first.n) } }
        if page.benefits.isEmpty && page.uses.isEmpty && page.sources.isEmpty && page.label.isEmpty && page.physiology.isEmpty {
            FACard {
                FAEmptyState(title: String(localized: "supplement.empty.title", defaultValue: "Nothing published here yet"),
                             message: String(localized: "supplement.empty.message", defaultValue: "Your practice adds the research as it is reviewed."))
            }
        }
    }

    // MARK: Pieces

    private var hero: some View {
        HStack(spacing: 12) {
            SupplementVisualView(visual: page.visual)
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FAColor.forestSoft)
                Text(page.name).font(FATypography.display(25, relativeTo: .title)).foregroundStyle(FAColor.ink)
                if let detail = visualDetail {
                    Text(detail).font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var eyebrow: String {
        let base = String(localized: "supplement.kicker", defaultValue: "Supplement")
        if let category = page.category, !category.isEmpty { return "\(base) · \(category)" }
        return base
    }

    /// Under the name: an element's number, a molecule's formula — the publisher's words, formatted only.
    private var visualDetail: String? {
        switch page.visual {
        case .elements(let elements):
            guard let first = elements.first, elements.count == 1 else { return nil }
            return String(localized: "supplement.element.detail", defaultValue: "Element \(first.number)")
        case .molecule(let molecule):
            return molecule.formula
        case nil:
            return nil
        }
    }

    private func chip(for useKey: String?) -> String? {
        guard let useKey, let use = page.uses.first(where: { $0.key == useKey }) else { return nil }
        return SupplementLogic.useChip(title: use.title, supplement: page.name)
    }

    private func items(_ list: [SupplementItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, item in
                SupplementItemRow(item: item, style: .bullet, sources: page.sources, onSource: onSource)
            }
        }
    }

    private func useRow(_ use: SupplementPage.UseRef) -> some View {
        let unsupported = use.evidence.level == .notSupported
        return Button { router.push(.supplementUse(use.slug)) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(use.title).font(FATypography.display(14, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).multilineTextAlignment(.leading)
                    EvidenceBadge(level: use.evidence.level)
                    if let summary = use.summary, !summary.isEmpty {
                        Text(summary).font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.stone).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.stone).accessibilityHidden(true)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Color.white.opacity(unsupported ? 0.55 : 0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(unsupported ? Color(hex: 0x9F2D3A, opacity: 0.35) : FAColor.forestSoft.opacity(0.22),
                                  style: StrokeStyle(lineWidth: 1, dash: unsupported ? [4, 3] : []))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(use.title) · \(use.evidence.level.label)")
    }

    private func foodChip(_ food: SupplementPage.Food) -> some View {
        let amount = food.amountMg.map { $0.formatted(.number.precision(.fractionLength(0...1))) }
        let detail = [food.portion, amount.map { String(localized: "supplement.food.mg", defaultValue: "\($0) mg") }]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 1) {
            Text(food.name).font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.ink)
            if !detail.isEmpty {
                Text(detail).font(FATypography.sans(8.5, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Color.white.opacity(0.85), in: Capsule())
        .overlay { Capsule().strokeBorder(FAColor.forestSoft.opacity(0.25), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}
