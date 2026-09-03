import SwiftUI

/// The Library tab — layout v2's order, vertical: plan header → chip rail → Priority for you →
/// Continue → Tracks → Foundations → Supplements (mockup "Library on the Phone", 2026-08-16).
struct LibraryView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: LibraryViewModel?

    var body: some View {
        ZStack {
            if let model {
                LibraryScreen(model: model)
            } else {
                FALoadingState()
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                let m = LibraryViewModel(library: dependencies.library, members: dependencies.members)
                model = m
                await m.load()
            }
        }
    }
}

private struct LibraryScreen: View {
    @Bindable var model: LibraryViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header
                    Section {
                        sections
                    } header: {
                        chipRail(proxy)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .refreshable { await model.load() }
        }
    }

    // MARK: Header + plan

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "library.title", defaultValue: "Library"))
                .font(FATypography.display(28, relativeTo: .largeTitle))
                .foregroundStyle(FAColor.ink)
            if !model.bundle.live {
                Text(String(localized: "library.sample", defaultValue: "Sample preview · sign in to see your own library"))
                    .font(FATypography.sans(11, .semibold, relativeTo: .caption))
                    .foregroundStyle(FAColor.inkSecondary)
            }
            if let plan = model.bundle.plan {
                planCard(plan).padding(.top, 12)
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 10)
    }

    /// The reason this library is personal — absorbs the desktop nav's ring + week.
    private func planCard(_ plan: PlanHeader) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ActivityRing(pct: model.pct, color: FAColor.forest, size: 52, strokeWidth: 6, hashedTrack: false, raised: false, trackColor: Color.black.opacity(0.08)) {
                        Text("\(Int((model.pct * 100).rounded()))%").font(FATypography.display(12, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text((String(localized: "library.plan.kicker", defaultValue: "Your care plan") + (model.week.map { String(localized: "library.plan.week", defaultValue: " · Week \($0)") } ?? "")).uppercased())
                            .font(FATypography.sans(9, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(FALibraryColor.gold)
                        Text(plan.title).font(FATypography.display(16, relativeTo: .headline)).foregroundStyle(FAColor.ink).lineLimit(2)
                        Text(String(localized: "library.plan.lessons", defaultValue: "\(model.doneTotal) of \(model.lessonTotal) lessons"))
                            .font(FATypography.sans(10.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    }
                }
                if !plan.objectives.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(plan.objectives.prefix(3), id: \.self) { o in
                            Text(o).font(FATypography.sans(10, .bold, relativeTo: .caption2)).foregroundStyle(FAColor.forest).lineLimit(1)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(FAColor.forest.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: Chip rail (sticky — the whole left nav, one thumb row)

    private func chipRail(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(LibraryViewModel.Section.allCases) { section in
                    if section == .priority && model.priority.isEmpty { EmptyView() } else {
                        let on = model.active == section
                        Button {
                            model.active = section
                            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(section.id, anchor: .top) }
                        } label: {
                            HStack(spacing: 5) {
                                Text(section.title).font(FATypography.sans(11, .bold, relativeTo: .caption)).foregroundStyle(on ? FAColor.cream : Color(hex: 0x4A4A42))
                                if let n = model.count(section) {
                                    Text("\(n)").font(FATypography.sans(11, relativeTo: .caption)).foregroundStyle(on ? FAColor.cream.opacity(0.7) : Color(hex: 0x4A4A42, opacity: 0.55))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(on ? FAColor.forest : Color.white.opacity(0.66), in: Capsule())
                            .overlay { Capsule().strokeBorder(on ? FAColor.forest : Color(hex: 0x1A1A16, opacity: 0.1), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .background(Color.clear)
    }

    // MARK: Sections

    @ViewBuilder
    private var sections: some View {
        let b = model.bundle
        if !model.priority.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                LibrarySectionHead(title: String(localized: "library.priority.title", defaultValue: "Priority for you"), note: String(localized: "library.priority.note", defaultValue: "chosen from your plan"))
                Veiled(open: b.access.tracks) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.priority) { t in
                                TrackCard(track: t, coverHeight: 96) { open(t) }.frame(width: 250)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.top, 8)
            .id(LibraryViewModel.Section.priority.id)
        }

        if !model.inProgress.isEmpty && b.access.tracks {
            VStack(alignment: .leading, spacing: 0) {
                LibrarySectionHead(title: String(localized: "library.continue.title", defaultValue: "Continue"), note: String(localized: "library.continue.note", defaultValue: "\(model.inProgress.count) in progress"))
                VStack(spacing: 10) {
                    ForEach(model.inProgress) { t in continueRow(t) }
                }
            }
            .padding(.top, 18)
        }

        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: String(localized: "library.section.tracks", defaultValue: "Tracks"), note: "\(b.tracks.count)")
            Veiled(open: b.access.tracks) {
                Grid2(items: LibraryLogic.visibleItems(b.tracks, expanded: model.expanded.contains(.tracks))) { t in
                    TrackCard(track: t) { open(t) }
                }
                MoreToggle(label: LibraryLogic.toggleLabel(total: b.tracks.count, expanded: model.expanded.contains(.tracks), noun: String(localized: "library.noun.tracks", defaultValue: "tracks")), expanded: model.expanded.contains(.tracks)) { model.toggle(.tracks) }
            }
        }
        .padding(.top, 18)
        .id(LibraryViewModel.Section.tracks.id)

        if !model.foundations.isEmpty {
            resourceSection(.foundations, items: model.foundations, open: b.access.foundations, noun: String(localized: "library.noun.resources", defaultValue: "resources"))
        }
        if !model.supplements.isEmpty {
            resourceSection(.supplements, items: model.supplements, open: b.access.supplements, noun: String(localized: "library.noun.supplements", defaultValue: "supplements"))
        }
    }

    private func resourceSection(_ section: LibraryViewModel.Section, items: [LibResource], open: Bool, noun: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: section.title, note: "\(items.count)")
            Veiled(open: open) {
                Grid2(items: LibraryLogic.visibleItems(items, expanded: model.expanded.contains(section))) { r in
                    ResourceCard(resource: r) { router.libraryPath.append(.read(r.slug)) }
                }
                MoreToggle(label: LibraryLogic.toggleLabel(total: items.count, expanded: model.expanded.contains(section), noun: noun), expanded: model.expanded.contains(section)) { model.toggle(section) }
            }
        }
        .padding(.top, 18)
        .id(section.id)
    }

    /// The resume card: cover strip · pillar kicker · next lesson · "Lesson n of N · resume".
    private func continueRow(_ t: TrackWithProgress) -> some View {
        Button { open(t) } label: {
            FACard(padded: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        PillarCover(pillar: t.pillar, height: 64, slug: t.slug).frame(width: 84)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title.uppercased()).font(FATypography.sans(8.5, .bold, relativeTo: .caption2)).tracking(1.1).foregroundStyle(FALibraryColor.gold)
                            Text(t.lessons.first { !$0.done }?.title ?? String(localized: "library.reviewTrack", defaultValue: "Review the track"))
                                .font(FATypography.display(13.5, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal).lineLimit(1)
                            Text(String(localized: "library.resume", defaultValue: "Lesson \(min(t.done + 1, t.total)) of \(t.total) · resume"))
                                .font(FATypography.sans(9.5, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
                        }
                        .padding(10)
                        Spacer(minLength: 0)
                    }
                    ProgressHairline(pct: t.pct)
                }
                .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }

    private func open(_ t: TrackWithProgress) {
        guard t.state != .locked else { return }
        router.libraryPath.append(.track(t.slug))
    }
}
