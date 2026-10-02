import SwiftUI

/// The bank of foundation actions (owner, 2026-10-02): the cards the practice lets members add themselves
/// (`habit_bank.member_can_add`), by pillar. Each opens its card — what it is, how, why, the library article —
/// with "Add to my plan". Adding makes the member's OWN habit; nothing here touches what the clinician prescribed.
/// States (rule 5): loading, failed with retry, empty (the practice has not opened any yet), loaded.
struct ActionBankView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let habits = dependencies.habits
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "bank.title", defaultValue: "Foundation actions"), hairline: true)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "bank.intro", defaultValue: "Small actions your practice recommends to everyone. Read about one, then add it to your plan."))
                        .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .faFrost(cornerRadius: 14, horizontal: 14, vertical: 10)
                    switch habits.bank {
                    case .idle, .loading:
                        FALoadingState().frame(maxWidth: .infinity).padding(.top, 30)
                    case .failed(let message):
                        FACard {
                            FAErrorState(title: String(localized: "bank.error", defaultValue: "Couldn't load the actions"), message: message) {
                                Task { await habits.retryBank() }
                            }
                        }
                    case .loaded(let cards):
                        if cards.isEmpty {
                            FACard {
                                FAEmptyState(title: String(localized: "bank.empty.title", defaultValue: "No actions to add yet"),
                                             message: String(localized: "bank.empty.message", defaultValue: "Your practice adds them here as they are written."))
                            }
                        } else {
                            ForEach(PlanAccess.bankByPillar(cards), id: \.pillar) { group in
                                pillarCard(group.pillar, cards: group.cards)
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, FASpacing.navBarClearance)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await habits.loadBank() }
    }

    private func pillarCard(_ pillar: String, cards: [ActionCardRow]) -> some View {
        let plan = dependencies.habits.plan
        let locale = TodayFocus.locale()
        return FACard {
            VStack(alignment: .leading, spacing: 6) {
                Text(PlanAccess.pillarLabel(pillar).uppercased())
                    .font(FATypography.sans(10, .bold, relativeTo: .caption2)).tracking(0.9).foregroundStyle(FAColor.inkSecondary)
                ForEach(cards) { card in
                    let kind = card.cardKind.flatMap(ActionCardKind.init(rawValue:))
                    let added = PlanAccess.habit(for: card.id, in: plan) != nil
                    NavigationLink(value: Route.bankCard(card.id)) {
                        HStack(spacing: 10) {
                            Image(systemName: kind?.symbol ?? "leaf").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.forest)
                                .frame(width: 34, height: 34)
                                .background(FAColor.forestSoft.opacity(0.14), in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ActionCardLogic.pick(card.title, card.titleFr, locale: locale) ?? card.title)
                                    .font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                    .multilineTextAlignment(.leading)
                                let meta = [kind?.label, card.durationMin.map { String(localized: "action.minutes", defaultValue: "\($0) min") }].compactMap { $0 }
                                if !meta.isEmpty {
                                    Text(meta.joined(separator: " · ")).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if added {
                                Label(String(localized: "bank.added", defaultValue: "Added"), systemImage: "checkmark")
                                    .font(FATypography.caption).foregroundStyle(FAColor.forest)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkMuted)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
