import SwiftUI

/// Track page — the members TrackHero + lesson list at phone scale: cover band, "why this is in
/// your plan" (priority tracks only), continue CTA, then the lesson rows (done ✓ · now · open · locked).
struct TrackView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    let slug: String
    @State private var track: TrackWithProgress?
    @State private var priority = false
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                backRow
                if let track {
                    hero(track)
                    lessons(track)
                } else if loaded {
                    FAErrorState(title: String(localized: "library.track.unavailable", defaultValue: "This track isn't available"), message: "", retryTitle: String(localized: "library.back", defaultValue: "Back to the library")) { dismiss() }
                } else {
                    FALoadingState()
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: slug) { await load() }
    }

    private func load() async {
        defer { loaded = true }
        if let demo = LibraryDemo.tracks.first(where: { $0.slug == slug }) { track = demo; return }
        guard let member = try? await dependencies.members.currentMember(),
              let bundle = await dependencies.library.bundle(patientId: member.patientId) else { return }
        track = bundle.tracks.first { $0.slug == slug }
        priority = bundle.prioritySlugs.contains(slug)
    }

    private var backRow: some View {
        Button { dismiss() } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.charcoal)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.66), in: Circle())
                    .overlay { Circle().strokeBorder(Color(hex: 0x1A1A16, opacity: 0.1), lineWidth: 1) }
                Text(String(localized: "library.title", defaultValue: "Library")).font(FATypography.sans(12, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func hero(_ t: TrackWithProgress) -> some View {
        let first = LibraryLogic.firstOpenIndex(t.lessons)
        let resume = t.lessons.isEmpty ? nil : t.lessons[min(first, t.lessons.count - 1)]
        return FACard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                PillarCover(pillar: t.pillar, height: 120, badge: t.state == .locked ? nil : t.badge.label, badgeTone: t.badge.tone,
                            lockLabel: t.state == .locked ? (t.lockLabel ?? String(localized: "library.locked", defaultValue: "Locked")) : nil, slug: t.slug)
                ProgressHairline(pct: t.pct)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(t.pillar) · \(String(localized: "library.lessons.count", defaultValue: "\(t.total) lessons"))".uppercased())
                        .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FALibraryColor.gold)
                    Text(t.title).font(FATypography.display(21, relativeTo: .title2)).foregroundStyle(FAColor.charcoal)
                    if !t.description.isEmpty {
                        Text(t.description).font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(FAColor.stone)
                    }
                    if priority {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "library.why.kicker", defaultValue: "Why this is in your plan").uppercased()).font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FAColor.forest)
                            Text(String(localized: "library.why.body", defaultValue: "Your practitioner put this first for you · start here before the rest.")).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(Color(hex: 0x4A4A42))
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FAColor.forestGlow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.top, 6)
                    }
                    if t.state != .locked, t.total > 0, t.state != .completed, let resume {
                        Button { router.libraryPath.append(.read(resume.contentSlug)) } label: {
                            Text(t.done > 0 ? String(localized: "library.continue.cta", defaultValue: "Continue · lesson \(first + 1) of \(t.total)") : String(localized: "library.start", defaultValue: "Start the track"))
                                .font(FATypography.sans(12.5, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.cream)
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(FAColor.forest, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(15)
            }
            .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
        }
    }

    /// The WHOLE TRACK decides whether its rows carry a preview, not each row.
    private func lessons(_ t: TrackWithProgress) -> some View {
        let first = LibraryLogic.firstOpenIndex(t.lessons)
        let illustrated = t.lessons.contains { $0.coverURL != nil }
        return FACard(padded: false) {
            VStack(spacing: 0) {
                ForEach(Array(t.lessons.enumerated()), id: \.element.id) { i, l in
                    let access: LessonAccess = t.state == .locked ? .locked : LibraryLogic.lessonAccess(index: i, first: first)
                    Button { router.libraryPath.append(.read(l.contentSlug)) } label: {
                        HStack(spacing: 10) {
                            if illustrated { ArticleCoverSlot(pillar: t.pillar, trackSlug: t.slug, coverURL: l.coverURL, radius: 8) }
                            statusDot(access, index: i)
                            Text(l.title).font(FATypography.display(13.5, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal).lineLimit(illustrated ? 2 : 1).multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            Text(accessLabel(access)).font(FATypography.sans(10, .bold, relativeTo: .caption2)).foregroundStyle(accessColor(access))
                        }
                        .padding(.horizontal, illustrated ? 10 : 13)
                        .padding(.vertical, illustrated ? 8 : 12)
                        .opacity(access == .locked ? 0.55 : 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(access == .locked)
                    if i < t.lessons.count - 1 { Divider().overlay(Color(hex: 0x1A1A16, opacity: 0.06)) }
                }
                if t.lessons.isEmpty {
                    Text(String(localized: "library.track.empty", defaultValue: "The lessons for this track are being written · check back soon."))
                        .font(FATypography.sans(12, relativeTo: .footnote)).foregroundStyle(FAColor.stone).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(18)
                }
            }
        }
    }

    private func statusDot(_ access: LessonAccess, index: Int) -> some View {
        ZStack {
            Circle().fill(access == .done ? FAColor.forest : access == .current ? FALibraryColor.goldMist : FALibraryColor.warm)
            Circle().strokeBorder(access == .done ? FAColor.forest : access == .current ? FALibraryColor.gold : Color(hex: 0x1A1A16, opacity: 0.1), lineWidth: 1)
            switch access {
            case .done: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            case .locked: Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(FALibraryColor.stoneLight)
            default: Text("\(index + 1)").font(FATypography.sans(10.5, .bold, relativeTo: .caption2)).foregroundStyle(access == .current ? FALibraryColor.gold : FALibraryColor.stoneLight)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private func accessLabel(_ a: LessonAccess) -> String {
        switch a {
        case .done: String(localized: "library.lesson.done", defaultValue: "Done")
        case .current: String(localized: "library.lesson.now", defaultValue: "Now")
        case .open: String(localized: "library.lesson.open", defaultValue: "Open")
        case .locked: ""
        }
    }
    private func accessColor(_ a: LessonAccess) -> Color {
        switch a {
        case .done: FAColor.forestSoft
        case .current: FALibraryColor.gold
        default: FALibraryColor.stoneLight
        }
    }
}
