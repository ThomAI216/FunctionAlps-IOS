import SwiftUI

/// "How this app works" — the Guide hub (the Expo `guide/index.tsx`): the overview hero on an opaque
/// reading surface, then the chapters grouped, then the fall-through to Help & FAQ.
struct GuideView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let hero = HelpCatalog.entry(HelpCatalog.heroKey)
        let groups = HelpCatalog.groups
            .map { HelpGroup(key: $0.key, title: $0.title, blurb: $0.blurb, entries: $0.entries.filter { $0.key != HelpCatalog.heroKey }) }
            .filter { !$0.entries.isEmpty }
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium)).foregroundStyle(FAColor.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
                    Text(String(localized: "profile.learn.title", defaultValue: "How this app works")).font(FATypography.display(24, relativeTo: .title)).foregroundStyle(FAColor.ink)
                }
                .padding(.vertical, 12)

                Text(String(localized: "guide.intro", defaultValue: "Every screen explained in plain language. Read the first three and you will understand the whole thing."))
                    .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5).padding(.bottom, 16)

                if let hero {
                    Button { router.profilePath.append(.guideChapter(hero.key)) } label: {
                        ReadingSurface(borderHex: 0x4A8A5C) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(hero.title).font(FATypography.display(21, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                                Text(hero.lede).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).padding(.top, 3)
                                Text(hero.body).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5).lineLimit(3).padding(.top, 10)
                                HStack(spacing: 6) {
                                    Text(String(localized: "guide.startHere", defaultValue: "Start here")).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                                }
                                .padding(.top, 12)
                                .overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
                                .padding(.top, 13)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title.uppercased()).font(FATypography.sans(11, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(ProfilePalette.muted)
                        Text(group.blurb).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                    }
                    .padding(.top, 24).padding(.bottom, 10)
                    ReadingSurface(padded: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.key) { i, entry in
                                Button { router.profilePath.append(.guideChapter(entry.key)) } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.title).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                            Text(entry.lede).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                                        }
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.muted)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .bottom) {
                                    if i < group.entries.count - 1 { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }
                                }
                            }
                        }
                    }
                }

                Button { router.profilePath.append(.help) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "questionmark.circle").font(.system(size: 15)).foregroundStyle(ProfilePalette.muted)
                        Text(String(localized: "guide.stillStuck", defaultValue: "Still stuck? Help & FAQ")).font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.muted)
                    }
                    .padding(15)
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(ProfilePalette.hairline) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 26)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One Guide chapter (the Expo `guide/[key].tsx`): title, lede, the paragraph + points on the opaque
/// surface, the footnote, and "Open this screen" when the chapter has one.
struct GuideChapterView: View {
    let key: String
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entry = HelpCatalog.entry(key)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium)).foregroundStyle(FAColor.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
                    Text(String(localized: "guide.title", defaultValue: "Guide")).font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                }
                .padding(.vertical, 12)

                if let entry {
                    Text(entry.title).font(FATypography.display(27, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink).lineSpacing(4)
                    Text(entry.lede).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).padding(.top, 4).padding(.bottom, 16)

                    ReadingSurface {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.body).font(FATypography.sans(14, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(6)
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(entry.points, id: \.label) { p in
                                    HStack(alignment: .top, spacing: 10) {
                                        Circle().fill(FAColor.forestSoft).frame(width: 6, height: 6).padding(.top, 7)
                                        (Text(p.label).font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundColor(FAColor.ink)
                                            + Text("  ")
                                            + Text(p.text).font(FATypography.sans(13.5, relativeTo: .subheadline)).foregroundColor(ProfilePalette.muted))
                                            .lineSpacing(5)
                                    }
                                }
                            }
                            .padding(.top, 16)
                            if let footnote = entry.footnote {
                                Text(footnote).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.ink).lineSpacing(4)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ProfilePalette.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x4A8A5C, opacity: 0.28), lineWidth: 1) }
                                    .padding(.top, 16)
                            }
                        }
                    }

                    if let tab = entry.opens {
                        Button {
                            router.profilePath.removeAll()
                            router.tab = tab
                        } label: {
                            Text(String(localized: "guide.openScreen", defaultValue: "Open this screen")).font(FATypography.sans(13.5, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(FAColor.forestSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 16)
                    }
                } else {
                    ReadingSurface {
                        Text(String(localized: "guide.notFound", defaultValue: "That page of the guide could not be found. Head back and pick another."))
                            .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(5)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
    }
}
