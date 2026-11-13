import SwiftUI

/// "Practice it": the habits a read (or a video) goes with. A habit already in the member's actions says "Open"; one
/// that is not gets a small "+ Add" when the practice lets members add the card themselves (`member_can_add`, the
/// same write the action bank uses). A card the member can neither open nor add is simply not listed.
struct LibraryPracticeSection: View {
    enum Source: Equatable {
        case article(slug: String)
        case video(url: URL)
    }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    let source: Source
    @State private var cards: [ActionCardRow] = []
    @State private var adding: String?
    @State private var addFailed = false

    private var items: [LibraryPracticeItem] {
        FoundationLibraryLogic.practiceItems(
            cards: cards, plan: dependencies.habits.plan,
            trackActions: FoundationLibraryLogic.trackActionRefs(days: dependencies.track.days, through: FoundationLibraryLogic.actionsThrough(status: dependencies.track.status)),
            locale: TodayFocus.locale()
        )
    }

    var body: some View {
        let shown = items
        Group {
            if !shown.isEmpty {
                FACard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "library.practice.title", defaultValue: "Practice it").uppercased())
                            .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FALibraryColor.gold)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().overlay(Color(hex: 0x1A1A16, opacity: 0.06)) }
                            row(item)
                        }
                        if addFailed {
                            Text(String(localized: "library.practice.addFailed", defaultValue: "Couldn't add it. Try again."))
                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        }
                    }
                }
            }
        }
        .task(id: source) { await load() }
    }

    private func row(_ item: LibraryPracticeItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(FATypography.sans(13.5, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink).multilineTextAlignment(.leading)
                Text(subtitle(item)).font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
            }
            Spacer(minLength: 8)
            switch item.action {
            case .open(let target):
                Button { open(target) } label: {
                    Text(String(localized: "library.practice.open", defaultValue: "Open"))
                        .font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .overlay { Capsule().strokeBorder(FAColor.forest.opacity(0.5), lineWidth: 1) }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "library.practice.openA11y", defaultValue: "Open \(item.title)"))
            case .add:
                Button { Task { await add(item) } } label: {
                    Text(adding == item.cardId ? String(localized: "state.saving", defaultValue: "Saving…") : String(localized: "library.practice.add", defaultValue: "+ Add"))
                        .font(FATypography.sans(11, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.forestSoft)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(adding != nil)
                .accessibilityLabel(String(localized: "library.practice.addA11y", defaultValue: "Add \(item.title) to your actions"))
            }
        }
    }

    private func subtitle(_ item: LibraryPracticeItem) -> String {
        let state: String
        switch item.action {
        case .open: state = String(localized: "library.practice.inActions", defaultValue: "in your actions")
        case .add: state = String(localized: "library.practice.notInActions", defaultValue: "not in your actions yet")
        }
        return [item.moment?.label, state].compactMap { $0 }.joined(separator: " · ")
    }

    private func open(_ target: LibraryHabitTarget) {
        switch target {
        case .habit(let id): router.push(.action(id))
        case .trackCard(let id, let face): router.push(.trackCard(id, face: face))
        }
    }

    private func add(_ item: LibraryPracticeItem) async {
        guard let card = cards.first(where: { $0.id == item.cardId }), adding == nil else { return }
        adding = item.cardId
        addFailed = false
        defer { adding = nil }
        await ensurePlan()
        let ok = await dependencies.habits.add(card: card, slot: card.defaultSlot.flatMap(HabitSlot.init(rawValue:)))
        addFailed = !ok
    }

    /// The member's plan, loaded when the screen is reached before Home has (a link, a restart on this tab).
    private func ensurePlan() async {
        guard dependencies.habits.plan == nil, let member = try? await dependencies.members.currentMember() else { return }
        await dependencies.habits.load(patientId: member.patientId, day: ISO8601.dayString(Date()))
    }

    private func load() async {
        await dependencies.habits.loadLadders()
        await ensurePlan()
        let all = dependencies.habits.ladderCards ?? []
        switch source {
        case .article(let slug): cards = FoundationLibraryLogic.cards(linkingArticle: slug, in: all)
        case .video(let url): cards = FoundationLibraryLogic.cards(linkingVideo: url, in: all)
        }
    }
}
