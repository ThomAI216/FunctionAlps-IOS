import SwiftUI

// The parts a supplement page and a use page are made of. Every sentence comes from the payload; the chrome
// (headings, "Open", "+ Add") is the app's.

/// A glass section: heading, optional note, content.
struct SupplementSection<Content: View>: View {
    let title: String
    var note: String? = nil
    var warn = false
    @ViewBuilder let content: Content

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(FATypography.sans(12.5, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    Spacer(minLength: 0)
                    if let note { Text(note).font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(FAColor.stone) }
                }
                content
            }
        }
        .overlay {
            if warn {
                RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous)
                    .strokeBorder(Color(hex: 0xC48B35, opacity: 0.35), lineWidth: 1)
                    .background(Color(hex: 0xC48B35, opacity: 0.08), in: RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
    }
}

/// One line of the payload with its badges. Tapping a line that cites sources opens them on the first one.
struct SupplementItemRow: View {
    enum Style { case check, bullet, plain }

    let item: SupplementItem
    var style: Style = .bullet
    /// The use the line belongs to, as a small tag after the text (the page's benefits).
    var tag: String? = nil
    let sources: [SourceRef]
    let onSource: (SourceKey) -> Void

    var body: some View {
        let cited = SupplementLogic.cited(item.sources, in: sources)
        HStack(alignment: .top, spacing: 8) {
            switch style {
            case .check:
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(FAColor.forestSoft)
                    .frame(width: 13, height: 13).padding(.top, 3).accessibilityHidden(true)
            case .bullet:
                Circle().fill(FAColor.forestSoft).frame(width: 5, height: 5).padding(.top, 7).accessibilityHidden(true)
            case .plain:
                EmptyView()
            }
            line
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .onTapGesture { if let first = cited.first { onSource(first.n) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(cited))
        .accessibilityHint(cited.isEmpty ? "" : String(localized: "supplement.sources.hint", defaultValue: "Shows the sources"))
        .accessibilityAddTraits(cited.isEmpty ? [] : .isButton)
    }

    private var line: Text {
        var t = Text(item.text).font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundColor(Color(hex: 0x33332C))
        if let tag, !tag.isEmpty {
            t = t + Text("  ") + Text(tag.uppercased()).font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).foregroundColor(FAColor.stone)
        }
        return t + SourceBadge.trail(item.sources)
    }

    private func accessibilityText(_ cited: [SourceRef]) -> String {
        var parts = [item.text]
        if let tag, !tag.isEmpty { parts.append(tag) }
        if !cited.isEmpty { parts.append(String(localized: "supplement.sources.count", defaultValue: "\(cited.count) sources")) }
        return parts.joined(separator: ", ")
    }
}

/// Label on the left, lines on the right ("Its job · Stored · Absorbed · Lowered by"). Rows with nothing to say
/// are left out.
struct SupplementKeyValues: View {
    let rows: [(label: String, items: [SupplementItem])]
    let sources: [SourceRef]
    let onSource: (SourceKey) -> Void

    var body: some View {
        let shown = rows.filter { !$0.items.isEmpty }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.label.uppercased())
                        .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(0.4).foregroundStyle(FAColor.stone)
                        .frame(width: 74, alignment: .leading).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(row.items.enumerated()), id: \.offset) { _, item in
                            SupplementItemRow(item: item, style: .plain, sources: sources, onSource: onSource)
                        }
                    }
                }
            }
        }
    }
}

/// "Goes with": the bank cards the payload names. In the member's actions → "Open" (its card); not yet → "+ Add",
/// which opens the bank card with its own "Add to my plan" (the routine caps live there). A card the bank does not
/// publish is skipped; a failed bank read hides the section (it is a side dish, never the meal).
struct GoesWithCard: View {
    let habitIds: [String]
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router

    var body: some View {
        let habits = dependencies.habits
        if !habitIds.isEmpty {
            switch habits.bank {
            case .idle, .loading:
                FACard { ProgressView().tint(FAColor.forestSoft).frame(maxWidth: .infinity) }
                    .task { await load() }
            case .failed:
                EmptyView()
            case .loaded(let cards):
                let found = habitIds.compactMap { id in cards.first { $0.id == id } }
                if !found.isEmpty {
                    FACard {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(String(localized: "supplement.goesWith", defaultValue: "Goes with").uppercased())
                                .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(FALibraryColor.gold)
                                .padding(.bottom, 8)
                            ForEach(Array(found.enumerated()), id: \.element.id) { i, card in
                                if i > 0 { Divider().overlay(Color.black.opacity(0.06)).padding(.vertical, 8) }
                                row(card, habit: PlanAccess.habit(for: card.id, in: habits.plan))
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ card: ActionCardRow, habit: HabitRow?) -> some View {
        let locale = TodayFocus.locale()
        let slot = card.defaultSlot.flatMap(HabitSlot.init(rawValue:))
        let title = ActionCardLogic.pick(card.title, card.titleFr, locale: locale) ?? card.title
        let status = habit != nil
            ? String(localized: "supplement.goesWith.in", defaultValue: "in your actions")
            : String(localized: "supplement.goesWith.notYet", defaultValue: "not in your actions yet")
        let meta = [slot?.label, status].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FATypography.sans(12.5, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                Text(meta).font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
            }
            Spacer(minLength: 0)
            if let habit {
                Button { router.push(.action(habit.id)) } label: {
                    Text(String(localized: "supplement.goesWith.open", defaultValue: "Open"))
                        .font(FATypography.sans(10.5, .bold, relativeTo: .caption)).foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 5).background(FAColor.forest, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "supplement.goesWith.open.a11y", defaultValue: "Open \(title)"))
            } else {
                Button { router.push(.bankCard(card.id)) } label: {
                    Text(String(localized: "supplement.goesWith.add", defaultValue: "+ Add"))
                        .font(FATypography.sans(10.5, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Color.white, in: Capsule())
                        .overlay { Capsule().strokeBorder(FAColor.forest, lineWidth: 1.5) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "supplement.goesWith.add.a11y", defaultValue: "Add \(title) to your plan"))
            }
        }
    }

    private func load() async {
        let habits = dependencies.habits
        await habits.loadBank()
        // The plan says "in your actions"; Home loads it, a direct link may not have.
        if habits.plan == nil, let member = try? await dependencies.members.currentMember() {
            await habits.load(patientId: member.patientId, day: ISO8601.dayString(Date()))
        }
    }
}

/// The articles the payload names, resolved from the bundle, two up.
struct SupplementArticles: View {
    let articles: [SupplementLogic.ArticleRef]
    @Environment(AppRouter.self) private var router

    var body: some View {
        if !articles.isEmpty {
            Grid2(items: articles) { article in
                Button { router.push(.read(article.slug)) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((article.track ?? String(localized: "supplement.article.kicker", defaultValue: "Read")).uppercased())
                            .font(FATypography.sans(8, .bold, relativeTo: .caption2)).tracking(0.6).foregroundStyle(FAColor.forestSoft).lineLimit(1)
                        Text(article.title).font(FATypography.display(12.5, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            .multilineTextAlignment(.leading).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.2), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(article.title)
            }
        }
    }
}

/// The sources card: "1 Mah & Pitre 2021 · 2 …", tap to see each one.
struct SupplementSourcesCard: View {
    let sources: [SourceRef]
    let onOpen: () -> Void

    var body: some View {
        if !sources.isEmpty {
            Button(action: onOpen) {
                SupplementSection(title: String(localized: "supplement.sources.title", defaultValue: "Sources"),
                                  note: String(localized: "supplement.sources.note", defaultValue: "\(sources.count) · tap to see each one")) {
                    Text(sources.map { "\($0.n.raw) \($0.label)" }.joined(separator: " · "))
                        .font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "supplement.sources.a11y.card", defaultValue: "\(sources.count) sources, opens the list"))
        }
    }
}

/// The lock note of a tier-locked row (the body is withheld server-side), in the reader's words.
struct SupplementLockNote: View {
    let reason: LockReason?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock").font(.system(size: 16, weight: .medium)).foregroundStyle(FALibraryColor.gold).accessibilityHidden(true)
            Text(reason == .membership
                 ? String(localized: "library.read.lock.membership", defaultValue: "This one comes with an active membership. The lessons you already have in this track stay open to you.")
                 : String(localized: "library.read.lock.programme", defaultValue: "This one opens as part of your program · your practitioner unlocks it."))
                .font(FATypography.sans(12.5, relativeTo: .footnote)).foregroundStyle(FAColor.stone).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous).strokeBorder(Color(hex: 0x1A1A16, opacity: 0.08), lineWidth: 1) }
    }
}
