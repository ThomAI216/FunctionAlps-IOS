import SwiftUI

/// "Your Pathway" — the items the practice chose for this member and sent with its messages
/// (`patient_message_resources`, CLINICAL migration 277). Owner, 2026-11-05: "They click on it. They arrive in the
/// library with a mini track specialized for them", and the page says what it rests on: "based on the consultation
/// from this moment, and our conversations on X, Y, Z". Every item is already unlocked for this member (the grant
/// came with the send), so nothing here is ever veiled.
struct SentTrackView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var items: [MessageResource] = []
    @State private var intro: PathwayIntro?
    @State private var tracks: [PersonalTrack] = []
    @State private var openedSlugs: Set<String> = []
    @State private var loaded = false

    private var opened: Int { items.filter { $0.openedAt != nil }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !loaded {
                    FALoadingState()
                } else if items.isEmpty && tracks.isEmpty {
                    FAEmptyState(
                        title: String(localized: "pathway.empty.title", defaultValue: "Your Pathway is on its way"),
                        message: String(localized: "pathway.empty.body", defaultValue: "When your practitioner answers you with something to read or try, it lands here.")
                    )
                } else {
                    ForEach(tracks) { track in
                        PersonalTrackCard(track: track, unopened: PersonalTrackLogic.unopened(track, openedSlugs: openedSlugs).count) {
                            router.libraryPath.append(.personalTrack(track.id))
                        }
                    }
                    if !items.isEmpty {
                        hero
                        list
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .navigationTitle(PathwayCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var hero: some View {
        FACard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                // The cover carries only what is new; "Curated for you" is the eyebrow below (once, not twice).
                PillarCover(pillar: "foundations", height: 120,
                            badge: items.count > opened ? String(localized: "library.sent.newCount", defaultValue: "\(items.count - opened) new") : nil,
                            badgeTone: .new)
                ProgressHairline(pct: items.isEmpty ? 0 : Int((Double(opened) / Double(items.count) * 100).rounded()))
                VStack(alignment: .leading, spacing: 6) {
                    Text(PathwayCopy.eyebrow.uppercased())
                        .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FALibraryColor.gold)
                    Text(PathwayCopy.title)
                        .font(FATypography.display(23, relativeTo: .title2)).foregroundStyle(FAColor.charcoal)
                    if let intro, let sentence = PathwayLogic.sentence(intro.basis) {
                        Text(sentence)
                            .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(Color(hex: 0x4A4A42)).lineSpacing(2)
                    }
                    if let focus = intro?.focus {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "pathway.focus", defaultValue: "Your focus").uppercased())
                                .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FAColor.forest)
                            Text(focus).font(FATypography.display(15, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FAColor.forestGlow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.top, 4)
                    }
                    Text(PathwayCopy.count(items.count, opened: opened))
                        .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.forest).padding(.top, 4)
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "pathway.items", defaultValue: "Chosen for you"))
                .font(FATypography.display(16.5, relativeTo: .headline)).foregroundStyle(FAColor.ink).padding(.top, 6)
            ForEach(items) { r in
                SentResourceRow(resource: r) { open(r) }
            }
        }
    }

    private func open(_ r: MessageResource) {
        if r.openedAt == nil { router.libraryBadge = max(0, router.libraryBadge - 1) }
        Task { await dependencies.messaging.markResourceOpened(id: r.id) }
        router.libraryPath.append(.read(r.slug))
    }

    private func load() async {
        items = await dependencies.messaging.sentResources()
        tracks = await dependencies.messaging.personalTracks()
        openedSlugs = await dependencies.messaging.openedSlugs()
        if let member = try? await dependencies.members.currentMember() {
            intro = await dependencies.messaging.pathwayIntro(patientId: member.patientId, items: items)
        }
        loaded = true
    }
}

/// The Pathway's two words, in one place (owner, 2026-11-05: "something that sounds more premium" than
/// personalised resources or education). Swapping the name is these two strings.
enum PathwayCopy {
    static var title: String { String(localized: "pathway.title", defaultValue: "Your Pathway") }
    static var eyebrow: String { String(localized: "pathway.eyebrow", defaultValue: "Curated for you") }
    /// "1 resource · 1 opened" / "3 resources · 1 opened" — never "1 resources".
    static func count(_ total: Int, opened: Int) -> String {
        total == 1
            ? String(localized: "library.sent.count.one", defaultValue: "1 resource · \(opened) opened")
            : String(localized: "library.sent.count", defaultValue: "\(total) resources · \(opened) opened")
    }
}

/// The Library's card for the Pathway: the same card family as a track.
struct SentTrackCard: View {
    let items: [MessageResource]
    let onPress: () -> Void

    var body: some View {
        let opened = items.filter { $0.openedAt != nil }.count
        let unopened = items.count - opened
        Button(action: onPress) {
            FACard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PillarCover(pillar: "foundations", height: 96,
                                badge: unopened > 0 ? String(localized: "library.sent.newCount", defaultValue: "\(unopened) new") : PathwayCopy.eyebrow,
                                badgeTone: unopened > 0 ? .new : .plain)
                    ProgressHairline(pct: items.isEmpty ? 0 : Int((Double(opened) / Double(items.count) * 100).rounded()))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PathwayCopy.eyebrow.uppercased())
                            .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                        Text(PathwayCopy.title)
                            .font(FATypography.display(15, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal).lineLimit(2).multilineTextAlignment(.leading)
                        HStack {
                            Text(PathwayCopy.count(items.count, opened: opened))
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
        .accessibilityLabel(PathwayCopy.title)
    }
}

/// Under a practice message in the thread: what came with it, and the way to the Pathway.
struct ResourcesAttachedCard: View {
    let resources: [MessageResource]
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "book").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.forest)
                    Text(String(localized: "messages.resources.attached", defaultValue: "Resources attached"))
                        .font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                    Text("\(resources.count)")
                        .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                        .background(FAColor.forestSoft, in: Capsule())
                }
                ForEach(resources) { r in
                    HStack(spacing: 6) {
                        Image(systemName: r.kind == .action ? "checklist" : "doc.text").font(.system(size: 11)).foregroundStyle(FAColor.stone)
                        Text(r.title).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineLimit(1)
                        if r.openedAt == nil {
                            Circle().fill(FAColor.forestSoft).frame(width: 6, height: 6)
                                .accessibilityLabel(String(localized: "library.sent.new", defaultValue: "Not opened yet"))
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text(String(localized: "messages.resources.findPathway", defaultValue: "Open your Pathway"))
                        .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forest)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(FAColor.forest)
                }
                .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FAColor.forestGlow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.28), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "messages.resources.attached", defaultValue: "Resources attached"))
    }
}

/// Home: the nudge toward the Pathway while something sent is unopened.
struct NewResourcesCard: View {
    let count: Int
    /// The team member's first name when known: "curated for you by Thomas".
    var from: String? = nil

    private var countLine: String {
        if let from, !from.isEmpty {
            return count == 1
                ? String(localized: "home.pathway.count.one.by", defaultValue: "1 resource curated for you by \(from)")
                : String(localized: "home.pathway.count.by", defaultValue: "\(count) resources curated for you by \(from)")
        }
        return count == 1
            ? String(localized: "home.pathway.count.one", defaultValue: "1 resource curated for you")
            : String(localized: "home.pathway.count", defaultValue: "\(count) resources curated for you")
    }

    var body: some View {
        FACard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(FAColor.forestSoft.opacity(0.14))
                    Image(systemName: "book").foregroundStyle(FAColor.forestSoft)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "home.pathway.new", defaultValue: "New in your Pathway"))
                        .font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    Text(countLine)
                        .font(FATypography.sans(13, relativeTo: .callout)).foregroundStyle(FAColor.inkSecondary)
                }
                Spacer()
                Text("\(count)")
                    .font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22)
                    .background(FAColor.forestSoft, in: Capsule())
                Image(systemName: "chevron.right").foregroundStyle(FAColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
