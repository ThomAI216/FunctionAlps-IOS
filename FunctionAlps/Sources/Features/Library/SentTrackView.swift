import SwiftUI

/// "Your practitioner's picks" — the mini track made of the items the practice sent with its messages
/// (`patient_message_resources`, CLINICAL migration 277). Owner, 2026-11-05: "They click on it. They arrive
/// in the library with a mini track specialized for them." Same anatomy as a track: a hero, then the items
/// as lessons, opened ones ticked. Every item is already unlocked for this member (the grant came with the
/// send), so nothing here is ever veiled.
struct SentTrackView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var items: [MessageResource] = []
    @State private var loaded = false

    private var opened: Int { items.filter { $0.openedAt != nil }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !loaded {
                    FALoadingState()
                } else if items.isEmpty {
                    FAEmptyState(
                        title: String(localized: "library.sent.empty.title", defaultValue: "Nothing sent yet"),
                        message: String(localized: "library.sent.empty.body", defaultValue: "When your practitioner answers you with a resource, it lands here.")
                    )
                } else {
                    hero
                    list
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .navigationTitle(String(localized: "library.sent.title", defaultValue: "Your practitioner's picks"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var hero: some View {
        FACard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                PillarCover(pillar: "foundations", height: 120, badge: String(localized: "library.sent.badge", defaultValue: "Sent for you"), badgeTone: .new)
                ProgressHairline(pct: items.isEmpty ? 0 : Int((Double(opened) / Double(items.count) * 100).rounded()))
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "library.section.sent", defaultValue: "From your practitioner").uppercased())
                        .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FALibraryColor.gold)
                    Text(String(localized: "library.sent.title", defaultValue: "Your practitioner's picks"))
                        .font(FATypography.display(21, relativeTo: .title2)).foregroundStyle(FAColor.charcoal)
                    Text(String(localized: "library.sent.description", defaultValue: "Chosen for you from your conversation. Read them in any order; each one stays here."))
                        .font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(FAColor.stone)
                    Text(String(localized: "library.sent.count", defaultValue: "\(items.count) resources · \(opened) opened"))
                        .font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.forest).padding(.top, 4)
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        }
    }

    private var list: some View {
        VStack(spacing: 8) {
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
        loaded = true
    }
}

/// The Library's card for the mini track: the same card family as a track, the practitioner's kicker.
struct SentTrackCard: View {
    let items: [MessageResource]
    let onPress: () -> Void

    var body: some View {
        let opened = items.filter { $0.openedAt != nil }.count
        let unopened = items.count - opened
        Button(action: onPress) {
            FACard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PillarCover(pillar: "foundations", height: 84, badge: unopened > 0 ? String(localized: "library.sent.newCount", defaultValue: "\(unopened) new") : String(localized: "library.sent.badge", defaultValue: "Sent for you"), badgeTone: unopened > 0 ? .new : .plain)
                    ProgressHairline(pct: items.isEmpty ? 0 : Int((Double(opened) / Double(items.count) * 100).rounded()))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "library.section.sent", defaultValue: "From your practitioner").uppercased())
                            .font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                        Text(String(localized: "library.sent.title", defaultValue: "Your practitioner's picks"))
                            .font(FATypography.display(14, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal).lineLimit(2).multilineTextAlignment(.leading)
                        HStack {
                            Text(String(localized: "library.sent.count", defaultValue: "\(items.count) resources · \(opened) opened"))
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
        .accessibilityLabel(String(localized: "library.sent.title", defaultValue: "Your practitioner's picks"))
    }
}

/// Under a practice message in the thread: what came with it, and the way to the mini track.
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
                    Text(String(localized: "messages.resources.find", defaultValue: "Find them in your library"))
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

/// Home: "New from your practitioner" — the nudge toward the mini track while something sent is unopened.
struct NewResourcesCard: View {
    let count: Int

    var body: some View {
        FACard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(FAColor.forestSoft.opacity(0.14))
                    Image(systemName: "book").foregroundStyle(FAColor.forestSoft)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "home.resources.new", defaultValue: "New from your practitioner"))
                        .font(FATypography.sans(15, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                    Text(String(localized: "home.resources.count", defaultValue: "\(count) resources to look at · in your library"))
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
