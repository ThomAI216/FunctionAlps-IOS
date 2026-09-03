import SwiftUI

/// The ONE card family for the phone library — the members TrackCard anatomy at phone scale:
/// pillar-gradient cover + state badge (+ lock veil), gold progress hairline, then pillar kicker ·
/// serif title · meta row. Wide (priority carousel), grid (2-up) and row (continue) are layouts
/// of the same parts. Every card sits on the app's clear glass.
enum FALibraryColor {
    static let gold = Color(hex: 0xC48B35)
    static let goldMist = Color(hex: 0xC48B35, opacity: 0.18)
    static let stoneLight = Color(hex: 0xA8A79E)
    static let warm = Color(hex: 0xFAF7F2)
}

struct PillarCover: View {
    enum BadgeTone { case plain, progress, new, done }

    let pillar: String
    var height: CGFloat
    var badge: String? = nil
    var badgeTone: BadgeTone = .plain
    var lockLabel: String? = nil
    /// Resolves the bundled cover art; without it (or without a file) the gradient stands in.
    var slug: String? = nil

    var body: some View {
        let (from, to) = LibraryLogic.pillarGradient(pillar)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: from), Color(hex: to)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let slug, LibraryLogic.bundledCovers.contains(slug), let art = FAMedia.image(slug) {
                // 16:9 masters composed with the subject in the middle third — `fill` crops top and bottom.
                Image(uiImage: art).resizable().scaledToFill()
            }
            LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.7, y: 0.9))
            if let badge {
                Text(badge.uppercased())
                    .font(FATypography.sans(8.5, .bold, relativeTo: .caption2))
                    .tracking(0.5)
                    .foregroundStyle(badgeForeground)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(badgeBackground, in: Capsule())
                    .padding(8)
            }
            if let lockLabel {
                ZStack {
                    Color.white.opacity(0.34)
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(FALibraryColor.gold)
                        Text(lockLabel).font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.charcoal)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.92), in: Capsule())
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    private var badgeBackground: Color {
        switch badgeTone {
        case .plain, .done: Color.white.opacity(0.88)
        case .progress: FALibraryColor.gold
        case .new: FAColor.forest
        }
    }
    private var badgeForeground: Color {
        switch badgeTone {
        case .plain: FAColor.stone
        case .done: FAColor.forest
        case .progress, .new: .white
        }
    }
}

/// The 84×64 article preview: this article's own infographic, else the track's cover art, else the
/// pillar gradient. The image FILLS the frame anchored top-left ("zoom in … align left and top").
struct ArticleCoverSlot: View {
    let pillar: String
    var trackSlug: String? = nil
    var coverURL: URL? = nil
    var width: CGFloat = 84
    var height: CGFloat = 64
    var radius: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            PillarCover(pillar: pillar, height: height, slug: coverURL == nil ? trackSlug : nil)
            if let url = LibraryLogic.storageThumbnail(coverURL, width: 512, height: 512) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                            .frame(width: width, height: height, alignment: .topLeading)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The gold progress hairline under a cover.
struct ProgressHairline: View {
    let pct: Int
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.08)
                FALibraryColor.gold.frame(width: geo.size.width * CGFloat(max(0, min(100, pct))) / 100)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

extension TrackWithProgress {
    var badge: (label: String?, tone: PillarCover.BadgeTone) {
        switch state {
        case .inProgress: (String(localized: "library.badge.inProgress", defaultValue: "In progress"), .progress)
        case .completed: (String(localized: "library.badge.done", defaultValue: "Done ✓"), .done)
        case .new: (String(localized: "library.badge.new", defaultValue: "New"), .new)
        case .locked: (nil, .plain)
        }
    }
}

struct TrackCard: View {
    let track: TrackWithProgress
    var coverHeight: CGFloat = 84
    let onPress: () -> Void

    var body: some View {
        let locked = track.state == .locked
        Button(action: onPress) {
            FACard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PillarCover(pillar: track.pillar, height: coverHeight, badge: locked ? nil : track.badge.label, badgeTone: track.badge.tone,
                                lockLabel: locked ? (track.lockLabel ?? String(localized: "library.locked", defaultValue: "Locked")) : nil, slug: track.slug)
                    ProgressHairline(pct: track.pct)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.pillar.uppercased()).font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                        Text(track.title).font(FATypography.display(14, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal).lineLimit(2).multilineTextAlignment(.leading)
                        HStack {
                            Text(String(localized: "library.lessons.count", defaultValue: "\(track.total) lessons")).font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
                            Spacer()
                            if !locked, track.total > 0 {
                                Text(String(localized: "library.lessons.done", defaultValue: "\(track.done) of \(track.total)"))
                                    .font(FATypography.sans(9.5, .bold, relativeTo: .caption2))
                                    .foregroundStyle(track.state == .completed ? FAColor.forestSoft : FAColor.charcoal)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(locked ? "\(track.title) · \(track.lockLabel ?? "locked")" : track.title)
    }
}

/// A standalone resource as the same card family (no progress, kicker meta).
struct ResourceCard: View {
    let resource: LibResource
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            FACard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PillarCover(pillar: resource.pillar, height: 56, badge: String(localized: "library.badge.resource", defaultValue: "Resource"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resource.pillar.uppercased()).font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                        Text(resource.title).font(FATypography.display(14, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal).lineLimit(2).multilineTextAlignment(.leading)
                        if !resource.summary.isEmpty {
                            Text(resource.summary).font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(FAColor.stone).lineLimit(2).multilineTextAlignment(.leading).padding(.top, 1)
                        }
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(resource.title)
    }
}

struct LibrarySectionHead: View {
    let title: String
    var note: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(title).font(FATypography.display(16.5, relativeTo: .headline)).foregroundStyle(FAColor.ink)
            if let note { Text(note).font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary) }
        }
        .padding(.bottom, 9)
    }
}

/// "There is more behind this". Renders NOTHING when the section already fits.
struct MoreToggle: View {
    let label: String?
    let expanded: Bool
    let onPress: () -> Void
    var body: some View {
        if let label {
            Button(action: onPress) {
                HStack(spacing: 6) {
                    Text(label).font(FATypography.sans(12.5, .bold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: FACornerRadius.sm, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }
}

/// The per-member activation veil — fail-closed like the web's SectionVeil: content renders
/// blurred-inert behind a lock note until the practitioner enables the section from CLINICAL.
struct Veiled<Content: View>: View {
    let open: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if open {
            content
        } else {
            content
                .opacity(0.45)
                .blur(radius: 1.5)
                .allowsHitTesting(false)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "lock").font(.system(size: 16, weight: .medium)).foregroundStyle(FAColor.inkSecondary)
                        Text(String(localized: "library.veil", defaultValue: "Your practitioner unlocks this section as part of your program"))
                            .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                }
                .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "library.veil", defaultValue: "Your practitioner unlocks this section as part of your program"))
        }
    }
}

/// Two columns, the Expo `Grid2`.
struct Grid2<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
            ForEach(items) { cell($0) }
        }
    }
}
