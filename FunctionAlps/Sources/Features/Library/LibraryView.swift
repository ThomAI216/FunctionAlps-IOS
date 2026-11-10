import SwiftUI

/// The Library tab (Thomas, 2026-11-10, the approved mockup): search at the top, then the Foundation Track day by
/// day, the reads tied to the member's habits, the videos that play in the app; below them, whatever the practice
/// prescribed (personal tracks, what it sent, priority tracks). No show, no pillar or topic lists, no tracks grid,
/// no supplements in this release.
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
        // Hidden here; it names the Library in the back button of the screens it opens ("‹ Bibliothèque").
        .navigationTitle(String(localized: "library.title", defaultValue: "Library"))
        .task {
            if model == nil {
                let m = LibraryViewModel(library: dependencies.library, members: dependencies.members, track: dependencies.track,
                                         habits: dependencies.habits, messaging: dependencies.messaging)
                model = m
                await m.load()
            }
        }
    }
}

private struct LibraryScreen: View {
    @Bindable var model: LibraryViewModel
    @Environment(AppRouter.self) private var router
    @FocusState private var searchFocused: Bool
    @State private var softLock: LibrarySoftLock?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    LibrarySearchField(text: $model.query, focused: $searchFocused).padding(.bottom, 14)
                    switch model.phase {
                    case .loading:
                        FALoadingState().frame(minHeight: 240)
                    case .failed(let message):
                        FACard {
                            FAErrorState(title: String(localized: "library.error.title", defaultValue: "Couldn't load the library"), message: message) {
                                Task { await model.load() }
                            }
                        }
                    case .unauthorized:
                        FACard {
                            FAEmptyState(title: String(localized: "library.unauthorized.title", defaultValue: "Please sign in again"),
                                         message: String(localized: "library.unauthorized.message", defaultValue: "Your session ended. Sign in to see your library."),
                                         systemImage: "lock")
                        }
                    case .loaded:
                        if model.isSearching { searchResults } else { content(proxy) }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, FASpacing.navBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.load() }
        }
        .sheet(item: $softLock) { lock in
            LibrarySoftLockSheet(lock: lock, today: model.today, dayTitle: model.dayTitle(lock.day))
        }
        .onAppear { Task { await model.refreshRead() } }
        #if DEBUG
        .task(id: model.phase) { await showcaseSoftLock() }
        #endif
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "library.title", defaultValue: "Library").uppercased())
                .font(FATypography.sans(10, .bold, relativeTo: .caption)).tracking(1.4).foregroundStyle(FAColor.inkSecondary)
            Text(String(localized: "library.tagline", defaultValue: "Learn at your pace"))
                .font(FATypography.display(28, relativeTo: .largeTitle)).foregroundStyle(FAColor.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    // MARK: Home

    @ViewBuilder
    private func content(_ proxy: ScrollViewProxy) -> some View {
        let groups = model.dayGroups
        let reads = model.habitReads
        let videos = model.videos
        if groups.isEmpty && reads.isEmpty && videos.isEmpty && !model.hasPrescribed {
            FACard {
                FAEmptyState(title: String(localized: "library.empty.title", defaultValue: "Nothing here yet"),
                             message: String(localized: "library.empty.message", defaultValue: "New reads appear here as they are published."))
            }
        }
        if !groups.isEmpty || !reads.isEmpty || !videos.isEmpty {
            LibraryChipRail(active: reads.isEmpty && model.anchor == .forYou ? .track : model.anchor, showForYou: !reads.isEmpty, showWatch: !videos.isEmpty) { anchor in
                model.anchor = anchor
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(anchor.rawValue, anchor: .top) }
            }
            .padding(.bottom, 14)
        }
        if !groups.isEmpty { trackSection(groups).id(LibraryViewModel.Anchor.track.rawValue) }
        if !reads.isEmpty { habitsSection(reads).id(LibraryViewModel.Anchor.forYou.rawValue) }
        if !videos.isEmpty { watchSection(videos).id(LibraryViewModel.Anchor.watch.rawValue) }
        if model.hasPrescribed { prescribedSection }
    }

    private func trackSection(_ groups: [LibraryDayGroup]) -> some View {
        let totals = FoundationLibraryLogic.readTotals(groups)
        return VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: String(localized: "library.track.title", defaultValue: "Your Foundation Track"),
                               note: String(localized: "library.track.progress", defaultValue: "\(totals.read) of \(totals.total) read"))
            ScrollViewReader { rail in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(groups) { group in
                            LibraryDayCard(group: group) { open(group) }.id(group.day)
                        }
                    }
                    .padding(.vertical, 2)
                }
                                .task(id: model.today) {
                    // Two days before today, like the mockup: the member lands on what is current, with the last reads behind.
                    guard let today = model.today, let first = groups.first(where: { $0.day >= today - 2 }) else { return }
                    rail.scrollTo(first.day, anchor: .leading)
                }
            }
        }
        .padding(.bottom, 20)
    }

    private func habitsSection(_ reads: [LibraryHabitRead]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: String(localized: "library.habits.title", defaultValue: "For your habits"),
                               note: String(localized: "library.habits.note", defaultValue: "tied to what you do now"))
            LibraryReadGrid(items: reads) { read in
                LibraryReadCard(kicker: read.habitTitle, title: read.article.title) { router.libraryPath.append(.read(read.article.slug)) }
            }
        }
        .padding(.bottom, 20)
    }

    private func watchSection(_ videos: [LibraryVideo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: String(localized: "library.watch.title", defaultValue: "Watch"),
                               note: String(localized: "library.watch.note", defaultValue: "plays in the app"))
            ScrollView(.horizontal, showsIndicators: false) {
                // A little space between the tiles, not much (Thomas, 2026-11-10).
                HStack(alignment: .top, spacing: 8) {
                    ForEach(videos) { video in
                        LibraryVideoTile(video: video) { router.libraryPath.append(.libraryVideo(video)) }.frame(width: 190)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: Search

    private var searchResults: some View {
        LibrarySearchResultsView(
            query: model.query, results: model.searchResults, today: model.today,
            onTopic: { model.query = $0.name },
            onArticle: { openArticle($0) },
            onHabit: { habit in
                switch habit.target {
                case .habit(let id): router.libraryPath.append(.action(id))
                case .trackCard(let id, let face): router.libraryPath.append(.trackCard(id, face: face))
                }
            },
            onVideo: { router.libraryPath.append(.libraryVideo($0)) }
        )
    }

    // MARK: Opening

    /// A day open to the member: its only read, or the page of its reads. A day still to come only says when it opens.
    private func open(_ group: LibraryDayGroup) {
        guard group.isOpenable else {
            softLock = LibrarySoftLock(day: group.day, titles: group.reads.map(\.title))
            return
        }
        if group.reads.count == 1, let only = group.reads.first {
            router.libraryPath.append(.read(only.slug))
        } else {
            router.libraryPath.append(.libraryDay(group.day))
        }
    }

    private func openArticle(_ article: LibraryArticle) {
        if let day = FoundationLibraryLogic.opensOn(article, today: model.today) {
            softLock = LibrarySoftLock(day: day, titles: [article.title])
        } else {
            router.libraryPath.append(.read(article.slug))
        }
    }

    // MARK: What the practice prescribed (kept)

    @ViewBuilder
    private var prescribedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibrarySectionHead(title: PathwayCopy.title, note: PathwayCopy.eyebrow.lowercased())
            ForEach(model.personal) { track in
                PersonalTrackCard(track: track, unopened: PersonalTrackLogic.unopened(track, openedSlugs: model.openedSlugs).count) {
                    router.libraryPath.append(.personalTrack(track.id))
                }
            }
            if !model.sent.isEmpty {
                SentTrackCard(items: model.sent) { router.libraryPath.append(.sentTrack) }
            }
            if !model.priority.isEmpty, let access = model.bundle?.access {
                Veiled(open: access.tracks) {
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
            if !model.continuing.isEmpty {
                VStack(spacing: 10) {
                    ForEach(model.continuing) { t in continueRow(t) }
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 4)
    }

    /// The resume card: cover strip · pillar kicker · next lesson · "Lesson n of N · resume".
    private func continueRow(_ t: TrackWithProgress) -> some View {
        Button { open(t) } label: {
            FACard(padded: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        PillarCover(pillar: t.pillar, height: 64, cover: t.cover).frame(width: 84)
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

    #if DEBUG
    /// The showcase's soft-lock shot: the sheet opens by itself on the day after today.
    private func showcaseSoftLock() async {
        guard Showcase.screen == .libraryLocked, model.phase == .loaded else { return }
        try? await Task.sleep(for: .seconds(1.2))
        guard let today = model.today, let group = model.dayGroups.first(where: { $0.day == today + 1 }) else { return }
        softLock = LibrarySoftLock(day: group.day, titles: group.reads.map(\.title))
    }
    #endif
}
