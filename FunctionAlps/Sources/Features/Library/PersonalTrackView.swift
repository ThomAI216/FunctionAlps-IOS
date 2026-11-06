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
    /// Actions the member put off with "Later" on this page: local only, nothing is stored (an action is done when it is
    /// in the plan, and that is the member's own act).
    private(set) var deferred: Set<String> = []
    private let trackId: String
    private let messaging: MessagingService
    private let auth: AuthService
    private let library: LibraryService
    private let members: MemberService

    init(trackId: String, messaging: MessagingService, auth: AuthService, library: LibraryService, members: MemberService) {
        self.trackId = trackId
        self.messaging = messaging
        self.auth = auth
        self.library = library
        self.members = members
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

    /// "Done, next" on an article: the same progress row the reader writes (`recordResourceOpen`), shown at once.
    func markDone(slug: String) async {
        markOpened(slug: slug)
        guard let member = try? await members.currentMember() else { return }
        await library.recordResourceOpen(patientId: member.patientId, slug: slug)
    }

    func putOff(_ itemId: String) { deferred.insert(itemId) }
}

/// One personal mini track, as the practice's gift: a hero with the progress, the practitioner's note, then the path
/// (numbered steps on a line, only the current one open) closed by a check-in. A library item opens in the reader
/// (already unlocked for this member by the send); an action card opens on its card, where "Add to my plan" is.
/// The words are the practice's; the app adds the frame only.
struct PersonalTrackView: View {
    let trackId: String
    /// The practitioner's name when the caller knows it; otherwise the care team's first name, else "your practitioner".
    var practitionerName: String? = nil
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model: PersonalTrackViewModel?
    /// The team's first member, when known: names the sender of the note and the check-in.
    @State private var teamFirstName: String?

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
                let m = PersonalTrackViewModel(trackId: trackId, messaging: dependencies.messaging, auth: dependencies.auth,
                                               library: dependencies.library, members: dependencies.members)
                model = m
                await m.load()
            }
        }
        .task { teamFirstName = await dependencies.messaging.careTeam().firstName }
        .task {
            // The plan says which actions are done; a link straight into the page may arrive before Home loaded it.
            if dependencies.habits.plan == nil, let member = try? await dependencies.members.currentMember() {
                await dependencies.habits.load(patientId: member.patientId, day: ISO8601.dayString(Date()))
            }
        }
        .refreshable { await model?.load() }
    }

    private var who: PractitionerWords { PractitionerWords(name: practitionerName ?? teamFirstName) }

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
            let planIds = PlanAccess.cardIds(in: dependencies.habits.plan)
            let steps = PersonalTrackLogic.steps(page.track, openedSlugs: page.openedSlugs, planCardIds: planIds, deferred: model?.deferred ?? [])
            let progress = PersonalTrackLogic.progress(page.track, openedSlugs: page.openedSlugs, planCardIds: planIds)
            if steps.isEmpty {
                PersonalTrackHero(title: page.track.title, sentAt: page.track.createdAt, done: 0, total: 0)
                FAEmptyState(
                    title: String(localized: "personalTrack.empty.title", defaultValue: "Nothing in this track yet"),
                    message: String(localized: "personalTrack.empty.body", defaultValue: "When your practitioner adds something, it appears here.")
                )
            } else {
                PersonalTrackHero(title: page.track.title, sentAt: page.track.createdAt, done: progress.done, total: progress.total)
                if !page.track.intro.isEmpty { PractitionerNote(intro: page.track.intro, words: who) }
                path(page, steps: steps)
                footer
            }
        }
    }

    private func path(_ page: PersonalTrackPage, steps: [PersonalTrackStep]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "personalTrack.path", defaultValue: "Your path"))
                .font(FATypography.display(16.5, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                .faFrost(cornerRadius: 12, horizontal: 12, vertical: 6)
                .padding(.bottom, 10)
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                PathStepRow(step: step, isLast: index == steps.count - 1) {
                    stepContent(step, page: page, steps: steps)
                }
            }
        }
    }

    @ViewBuilder
    private func stepContent(_ step: PersonalTrackStep, page: PersonalTrackPage, steps: [PersonalTrackStep]) -> some View {
        switch step.kind {
        case .item(let item):
            let title = page.title(for: item)
            if step.state == .current {
                CurrentItemCard(
                    title: title, item: item,
                    primary: { open(item) },
                    secondary: secondary(for: step, item: item, steps: steps)
                )
            } else {
                CollapsedStepRow(title: title, kindLabel: kindLabel(item), done: step.state == .done) { open(item) }
            }
        case .checkIn:
            if step.state == .current {
                CheckInCard(words: who) { router.open(PersonalTrackLogic.messagesURL) }
            } else {
                CollapsedStepRow(title: who.checkInTitle, kindLabel: String(localized: "personalTrack.checkin.kind", defaultValue: "Check-in"), done: false) {
                    router.open(PersonalTrackLogic.messagesURL)
                }
            }
        }
    }

    private func secondary(for step: PersonalTrackStep, item: PersonalTrackItem, steps: [PersonalTrackStep]) -> CurrentItemCard.Secondary? {
        switch item.kind {
        case .article(let slug):
            return .init(title: String(localized: "personalTrack.doneNext", defaultValue: "Done, next")) {
                if let model, case .loaded(let page) = model.phase, !PersonalTrackLogic.isOpened(item, openedSlugs: page.openedSlugs) {
                    router.libraryBadge = max(0, router.libraryBadge - 1)
                }
                Task { await model?.markDone(slug: slug) }
            }
        case .action:
            guard PersonalTrackLogic.canPutOff(step, in: steps, deferred: model?.deferred ?? []) else { return nil }
            return .init(title: String(localized: "personalTrack.later", defaultValue: "Later")) { model?.putOff(item.id) }
        }
    }

    private func kindLabel(_ item: PersonalTrackItem) -> String {
        if case .action = item.kind { return String(localized: "library.badge.action", defaultValue: "Action") }
        return String(localized: "library.badge.resource", defaultValue: "Resource")
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button { router.open(PersonalTrackLogic.messagesURL) } label: {
                Text(who.questionLine)
                    .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forest)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .faFrost(cornerRadius: 14, horizontal: 14, vertical: 0)
            }
            .buttonStyle(.plain)
            Text(String(localized: "personalTrack.stays", defaultValue: "It stays in your Library under Your Pathway."))
                .font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                .multilineTextAlignment(.center)
                .faFrost(cornerRadius: 12, horizontal: 12, vertical: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
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

/// The words that name the practitioner, or "your practitioner" while the app does not know the name.
struct PractitionerWords: Equatable {
    var name: String?

    private var clean: String? {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? nil : n
    }

    /// "Anna" or "Your practitioner" (a heading).
    var noteName: String { clean ?? String(localized: "personalTrack.practitioner.cap", defaultValue: "Your practitioner") }
    var initials: String? { PersonalTrackLogic.initials(clean) }
    var checkInTitle: String {
        clean.map { String(localized: "personalTrack.checkin.title", defaultValue: "Tell \($0) what changed") }
            ?? String(localized: "personalTrack.checkin.title.generic", defaultValue: "Tell your practitioner what changed")
    }
    var writeButton: String {
        clean.map { String(localized: "personalTrack.write", defaultValue: "Write to \($0)") }
            ?? String(localized: "personalTrack.write.generic", defaultValue: "Write to your practitioner")
    }
    var questionLine: String {
        clean.map { String(localized: "personalTrack.question", defaultValue: "A question? Write to \($0)") }
            ?? String(localized: "personalTrack.question.generic", defaultValue: "A question? Write to your practitioner")
    }
    /// " by Anna" on the message card's eyebrow; nil when unknown.
    var madeBy: String? { clean }
}

extension PersonalTrackLogic {
    static let messagesURL = URL(string: "functionalps://messages")!
}

/// Deep forest card: when it was sent, the title, how far along.
struct PersonalTrackHero: View {
    let title: String
    let sentAt: Date
    let done: Int
    let total: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [FAColor.forest, FAColor.forestDark], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Lower than the top edge so the peak shows whole (Thomas, 2026-11-06); the right edge still crops it, like a bookmark.
            FAMarkGlyph(color: .white.opacity(0.10), size: 120).offset(x: 18, y: 18)
            VStack(alignment: .leading, spacing: 8) {
                Text(PersonalTrackLogic.heroEyebrow(sentAt: sentAt).uppercased())
                    .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FAColor.forestMist)
                Text(title)
                    .font(FATypography.display(26, relativeTo: .title)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if total > 0 {
                    Text(PersonalTrackLogic.progressLabel(done: done, total: total))
                        .font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(.white.opacity(0.92))
                        .padding(.top, 6)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.22))
                            Capsule().fill(FAColor.forestMist).frame(width: geo.size.width * PersonalTrackLogic.progressFraction(done: done, total: total))
                        }
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// The practitioner's own letter: plain text, line breaks kept.
struct PractitionerNote: View {
    let intro: String
    let words: PractitionerWords

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(FAColor.forestGlow)
                        if let initials = words.initials {
                            Text(initials).font(FATypography.sans(13, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                        } else {
                            Image(systemName: "person.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(FAColor.forest)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "personalTrack.noteFrom", defaultValue: "A note from").uppercased())
                            .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FAColor.stone)
                        Text(words.noteName).font(FATypography.display(16, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    }
                }
                .accessibilityElement(children: .combine)
                Text(intro)
                    .font(FATypography.sans(14.5, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// One step on the line: the dot (a tick when done, the number otherwise, ringed when current), the line down to
/// the next dot (filled once the step is done), and the step's content.
struct PathStepRow<Content: View>: View {
    let step: PersonalTrackStep
    let isLast: Bool
    @ViewBuilder let content: Content

    private let dot: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                dotView
                if !isLast {
                    Rectangle()
                        .fill(step.state == .done ? FAColor.forest : FAColor.stoneLight.opacity(0.55))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 3)
                }
            }
            .frame(width: dot)
            .accessibilityHidden(true)
            content
                .padding(.bottom, isLast ? 0 : 12)
        }
    }

    @ViewBuilder
    private var dotView: some View {
        ZStack {
            switch step.state {
            case .done:
                Circle().fill(FAColor.forest)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            case .current:
                Circle().fill(Color.white)
                Circle().strokeBorder(FAColor.forest, lineWidth: 2)
                Text("\(step.number)").font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
            case .upcoming:
                Circle().fill(Color.white.opacity(0.7))
                Circle().strokeBorder(FAColor.stoneLight, lineWidth: 1.5)
                Text("\(step.number)").font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.stone)
            }
        }
        .frame(width: dot, height: dot)
        .background {
            if step.state == .current { Circle().fill(FAColor.forestMist.opacity(0.7)).frame(width: dot + 8, height: dot + 8) }
        }
    }
}

/// The step the member is on: the only one drawn as a card.
struct CurrentItemCard: View {
    struct Secondary {
        let title: String
        let action: () -> Void
    }

    let title: String
    let item: PersonalTrackItem
    let primary: () -> Void
    let secondary: Secondary?

    private var isAction: Bool { if case .action = item.kind { true } else { false } }

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: isAction ? "checklist" : "book")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.forest).accessibilityHidden(true)
                    Text(((isAction
                           ? String(localized: "library.badge.action", defaultValue: "Action")
                           : String(localized: "library.badge.resource", defaultValue: "Resource")) + " · " + String(localized: "personalTrack.today", defaultValue: "Today")).uppercased())
                        .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FAColor.forest)
                }
                Text(title)
                    .font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                FAButton(title: isAction ? String(localized: "bank.add", defaultValue: "Add to my plan")
                                         : String(localized: "personalTrack.read", defaultValue: "Read it"), action: primary)
                if let secondary {
                    FAButton(title: secondary.title, style: .tertiary, action: secondary.action)
                }
            }
        }
    }
}

/// A step that is not the current one: kind and title on one row; done ones are dimmed and carry a "Done" word.
struct CollapsedStepRow: View {
    let title: String
    let kindLabel: String
    let done: Bool
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kindLabel.uppercased())
                        .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FAColor.stone)
                    Text(title)
                        .font(FATypography.display(15, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if done {
                    Text(String(localized: "personalTrack.done", defaultValue: "Done"))
                        .font(FATypography.sans(11, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.forest)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.stoneLight)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FAGlassSurface(cornerRadius: 14, inset: true))
            .opacity(done ? 0.62 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "\(title), \(String(localized: "personalTrack.done", defaultValue: "Done"))" : title)
    }
}

/// The last step, always: tell the practitioner what changed.
struct CheckInCard: View {
    let words: PractitionerWords
    let onWrite: () -> Void

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.forest).accessibilityHidden(true)
                    Text((String(localized: "personalTrack.checkin.kind", defaultValue: "Check-in") + " · " + String(localized: "personalTrack.today", defaultValue: "Today")).uppercased())
                        .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FAColor.forest)
                }
                Text(words.checkInTitle)
                    .font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                FAButton(title: words.writeButton, action: onWrite)
            }
        }
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

/// Under a practice message: the track it came with. A deep band ("Made for you", the title), then one tile per
/// pick, the count and an "Open" pill; one tap opens the track page.
struct PersonalTrackMessageCard: View {
    let summary: PersonalTrackSummary
    /// The practitioner's name when the thread knows it (it does not yet): "Made for you by Anna".
    var madeBy: String? = nil
    let onPress: () -> Void

    private let maxTiles = 6

    var body: some View {
        Button(action: onPress) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FAColor.forestMist)
                    Text(summary.title)
                        .font(FATypography.display(19, relativeTo: .title3)).foregroundStyle(.white)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [FAColor.forest, FAColor.forestDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                HStack(spacing: 6) {
                    ForEach(Array(summary.actionFlags.prefix(maxTiles).enumerated()), id: \.offset) { _, isAction in
                        Image(systemName: isAction ? "checklist" : "book")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.forest)
                            .frame(width: 30, height: 30)
                            .background(FAColor.forestGlow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    if summary.actionFlags.count > maxTiles {
                        Text("+\(summary.actionFlags.count - maxTiles)")
                            .font(FATypography.sans(11, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
                    }
                    Spacer(minLength: 6)
                    Text(PersonalTrackLogic.picksLabel(summary.itemCount))
                        .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.stone)
                    Text(String(localized: "personalTrack.open", defaultValue: "Open"))
                        .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(FAColor.forest, in: Capsule())
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.white.opacity(0.85))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.28), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(eyebrow), \(PersonalTrackLogic.messageLabel(summary))")
        .accessibilityHint(String(localized: "personalTrack.open.hint", defaultValue: "Opens the track"))
    }

    private var eyebrow: String {
        let base = String(localized: "personalTrack.madeForYou", defaultValue: "Made for you")
        guard let madeBy, !madeBy.isEmpty else { return base }
        return String(localized: "personalTrack.madeForYouBy", defaultValue: "Made for you by \(madeBy)")
    }
}
