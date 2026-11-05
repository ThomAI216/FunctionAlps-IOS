import SwiftUI

/// What the page is showing. A track the member cannot read (withdrawn, not theirs, not approved) is `.missing`:
/// RLS answers with no row, never with a different error, so there is nothing more to say than "not available".
@MainActor
@Observable
final class PersonalTrackViewModel {
    enum Phase: Equatable {
        case loading
        case loaded(PersonalTrackPage)
        case missing
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private let trackId: String
    private let messaging: MessagingService
    private let auth: AuthService

    init(trackId: String, messaging: MessagingService, auth: AuthService) {
        self.trackId = trackId
        self.messaging = messaging
        self.auth = auth
    }

    func load() async {
        do {
            if let page = try await messaging.personalTrackPage(id: trackId) {
                phase = .loaded(page)
            } else {
                phase = .missing
            }
        } catch {
            if case AppError.unauthorized = error { await auth.handleUnauthorized(); return }
            phase = .failed((error as? AppError)?.userMessage ?? String(localized: "error.generic", defaultValue: "Something went wrong. Please try again."))
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    /// The member opened an article of the track: shown as opened at once (the reader writes the progress row).
    func markOpened(slug: String) {
        guard case .loaded(let page) = phase else { return }
        phase = .loaded(PersonalTrackPage(track: page.track, titles: page.titles, openedSlugs: page.openedSlugs.union([slug])))
    }
}

/// One personal mini track: the practitioner's message, then the items in order. A library item opens in the
/// reader (already unlocked for this member by the send); an action card opens on its card, where "Add to my plan"
/// is. The words are the practice's; the app adds the frame only.
struct PersonalTrackView: View {
    let trackId: String
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model: PersonalTrackViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .navigationTitle(PathwayCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                let m = PersonalTrackViewModel(trackId: trackId, messaging: dependencies.messaging, auth: dependencies.auth)
                model = m
                await m.load()
            }
        }
        .refreshable { await model?.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model?.phase ?? .loading {
        case .loading:
            FALoadingState()
        case .failed(let message):
            FAErrorState(title: String(localized: "personalTrack.error.title", defaultValue: "Couldn't load this track"), message: message) {
                Task { await model?.retry() }
            }
        case .missing:
            FAEmptyState(
                title: String(localized: "personalTrack.missing.title", defaultValue: "This track is not available"),
                message: String(localized: "personalTrack.missing.body", defaultValue: "Your practitioner may have changed it. Your Pathway keeps what is current.")
            )
        case .loaded(let page):
            if page.track.items.isEmpty {
                hero(page)
                FAEmptyState(
                    title: String(localized: "personalTrack.empty.title", defaultValue: "Nothing in this track yet"),
                    message: String(localized: "personalTrack.empty.body", defaultValue: "When your practitioner adds something, it appears here.")
                )
            } else {
                hero(page)
                list(page)
            }
        }
    }

    private func hero(_ page: PersonalTrackPage) -> some View {
        let track = page.track
        let opened = PersonalTrackLogic.openedCount(track, openedSlugs: page.openedSlugs)
        let articles = track.items.filter { $0.slug != nil }.count
        return FACard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                PillarCover(pillar: "foundations", height: 120)
                ProgressHairline(pct: articles == 0 ? 0 : Int((Double(opened) / Double(articles) * 100).rounded()))
                VStack(alignment: .leading, spacing: 8) {
                    Text(PathwayCopy.eyebrow.uppercased())
                        .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FALibraryColor.gold)
                    Text(track.title)
                        .font(FATypography.display(23, relativeTo: .title2)).foregroundStyle(FAColor.charcoal)
                    Text(PersonalTrackLogic.countLabel(track.items.count))
                        .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.forest)
                    if !track.intro.isEmpty {
                        // The practitioner's own message, as written: plain text, line breaks kept.
                        Text(track.intro)
                            .font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(Color(hex: 0x4A4A42)).lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(FAColor.forestGlow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.top, 2)
                    }
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        }
    }

    private func list(_ page: PersonalTrackPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "pathway.items", defaultValue: "Chosen for you"))
                .font(FATypography.display(16.5, relativeTo: .headline)).foregroundStyle(FAColor.ink).padding(.top, 6)
            ForEach(page.track.items) { item in
                PersonalTrackItemRow(title: page.title(for: item), item: item, opened: PersonalTrackLogic.isOpened(item, openedSlugs: page.openedSlugs)) {
                    open(item)
                }
            }
        }
    }

    private func open(_ item: PersonalTrackItem) {
        switch item.kind {
        case .article(let slug):
            if let model, case .loaded(let page) = model.phase, !PersonalTrackLogic.isOpened(item, openedSlugs: page.openedSlugs) {
                router.libraryBadge = max(0, router.libraryBadge - 1)
                model.markOpened(slug: slug)
            }
            router.libraryPath.append(.read(slug))
        case .action(let cardId):
            // An action card is offered, never opened as an article: its card has "Add to my plan".
            router.libraryPath.append(.bankCard(cardId))
        }
    }
}

/// One step of a personal track: an article to read, or an action card to add to the plan.
struct PersonalTrackItemRow: View {
    let title: String
    let item: PersonalTrackItem
    let opened: Bool
    let onPress: () -> Void

    private var isAction: Bool { if case .action = item.kind { true } else { false } }

    var body: some View {
        Button(action: onPress) {
            FACard(padded: false) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FAColor.forestSoft.opacity(0.14))
                        Image(systemName: isAction ? "checklist" : "book")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(FAColor.forest)
                    }
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((isAction
                              ? String(localized: "library.badge.action", defaultValue: "Action")
                              : String(localized: "library.badge.resource", defaultValue: "Resource")).uppercased())
                            .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                        Text(title).font(FATypography.display(14, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal).lineLimit(2).multilineTextAlignment(.leading)
                        if isAction {
                            Text(String(localized: "bank.add", defaultValue: "Add to my plan"))
                                .font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                        }
                    }
                    Spacer(minLength: 0)
                    if !isAction && !opened {
                        Circle().fill(FAColor.forestSoft).frame(width: 7, height: 7)
                            .accessibilityLabel(String(localized: "library.sent.new", defaultValue: "Not opened yet"))
                    }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.stoneLight)
                        .accessibilityHidden(true)
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The Library's card for one personal track: its name, how many things it holds, the start of the message.
struct PersonalTrackCard: View {
    let track: PersonalTrack
    let unopened: Int
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            FACard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PillarCover(pillar: "foundations", height: 96,
                                badge: unopened > 0 ? String(localized: "library.sent.newCount", defaultValue: "\(unopened) new") : PathwayCopy.eyebrow,
                                badgeTone: unopened > 0 ? .new : .plain)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(PathwayCopy.eyebrow.uppercased())
                            .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                        Text(track.title)
                            .font(FATypography.display(15, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal).lineLimit(2).multilineTextAlignment(.leading)
                        if let preview = PersonalTrackLogic.introPreview(track.intro) {
                            Text(preview)
                                .font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(Color(hex: 0x4A4A42)).lineLimit(3).multilineTextAlignment(.leading)
                        }
                        HStack {
                            Text(PersonalTrackLogic.countLabel(track.items.count))
                                .font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.stoneLight)
                        }
                        .padding(.top, 4)
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(track.title)
    }
}

/// Under a practice message: the track it came with, one tap to open it.
struct PersonalTrackMessageCard: View {
    let summary: PersonalTrackSummary
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            HStack(spacing: 8) {
                Image(systemName: "book").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.forest)
                VStack(alignment: .leading, spacing: 1) {
                    Text(PathwayCopy.eyebrow.uppercased())
                        .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                    Text(PersonalTrackLogic.messageLabel(summary))
                        .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(FAColor.forest)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FAColor.forestGlow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.28), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PersonalTrackLogic.messageLabel(summary))
    }
}
