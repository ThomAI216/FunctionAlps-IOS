import SwiftUI

/// Type-safe navigation routes. Each tab owns a `NavigationStack` bound to one path.
enum Route: Hashable {
    case profile
    case settings
    case meal(String)
    case checkin(MomentSlot)
    case track(String)
    case read(String)
    /// One Foundation Track day's reads, on their own page (Library → a day with several reads).
    case libraryDay(Int)
    /// A habit's video, played in the app (Library → Watch).
    case libraryVideo(LibraryVideo)
    /// The mini track of what the practice sent with its messages ("Your practitioner's picks").
    case sentTrack
    /// One personal mini track the practice built for this member (`patient_tracks`), by its id.
    case personalTrack(String)
    /// One episode of "The FunctionAlps Show" (Library), by its event slug.
    case episode(String)
    // Profile tab subpages (the Expo `(screens)/profile-*`, `guide`, `privacy-*`, `legal/*`)
    case carePlan
    /// The client's care plan screens (CLINICAL 2026-11-12): one objective, "Why we're doing this", "Your situation &
    /// evolution", and the journey (more than one programme).
    case clientObjective(String)
    case carePlanWhy
    case carePlanSituation
    case carePlanJourney
    case carePlanFocus(String)
    case carePlanAction(String)
    /// One action of the plan (a habit), opened on its action card.
    case action(String)
    /// One supplement's page (Home's "Supplements today", the Plan's list), by its plan id.
    case supplement(String)
    /// The bank of foundation actions a member may add themselves, and one card of it.
    case actionBank
    case bankCard(String)
    /// A Foundation Track action's card (`habit_bank` id), on the version the day shows (`easy` · `standard` · `further`).
    case trackCard(String, face: String)
    /// One Foundation Track habit's page (Home's actions card → "See the habit"), by its action key.
    case habit(String)
    /// The Foundation Track's approved day-7 summary.
    case trackSummary
    /// The Foundation Track's day as its own page (Home's track card opens it).
    case trackDay
    case baseline
    case feedback
    case guide
    case guideChapter(String)
    case privacy
    case consents
    case viewData
    case legal(String)
    case messages
    /// Messages opened FROM a meal: the thread starts with that meal as its context chip.
    case messagesAbout(mealId: String, name: String?)
    case help
    case wearables
    /// The member's own Apple Health page (today next to their week).
    case health
    // Macros & micros (the Expo `macros-details`, `nutrition-macros`, `micronutrients`, `micro-group/*`, `micro-nutrient/*`)
    case macros
    case nutritionTargets
    case micronutrients
    case microGroup(String)
    case microNutrient(String)
    case macro(String)
    case notifications
    case gutCheckin
    case gutIntelligence
    // The scores hub (the Expo `(screens)/scores`) and its signal pages (`score/[key]`)
    case scores
    case bodySignal(BodySignal)
    case gutSignal(GutSignal)
    // Released lab results (labs workspace v2, WP-7b): the list, one release, one marker of it
    case labResults
    case labResult(String)
    case labMarker(releaseId: String, markerId: String)
    /// What the care team released to the member: reports, lab reports, resources, invoices.
    case documents
    // Trends rework (2026-11-10): one signal's page, one device's page (`TrendsEngine.appleHealthKey` or a vendor key),
    // and the patterns the practitioner shared.
    case trendSignal(TrendSignal)
    case trendDevice(String)
    case trendPatterns
    /// "About <signal>": the practice's explanation of one signal (`SignalAboutKey`: sleep · energy · focus · mood · stress ·
    /// digestion · score), from its Trends row, its page, or the Functional score card.
    case signalAbout(String)
}

@MainActor
@Observable
final class AppRouter {
    var homePath: [Route] = []
    var trendsPath: [Route] = []
    var foodPath: [Route] = []
    var libraryPath: [Route] = []
    var profilePath: [Route] = []

    /// The web app's five tabs, in its order.
    enum Tab: Hashable, CaseIterable { case home, trends, food, library, profile }
    var tab: Tab = .home
    /// Items the practice sent and the member never opened — the Library tab's badge (refreshed on each tab change).
    var libraryBadge = 0
    /// The pillar the Trends tab should open on arrival (the hub's pillar tiles); consumed once.
    var pendingPillar: MemberScores.Pillar?

    /// The scores hub's way into the Trends tab: switch, pop, and hand over the pillar to expand.
    func openTrends(pillar: MemberScores.Pillar?) {
        pendingPillar = pillar
        trendsPath = []
        tab = .trends
    }

    /// Push onto the selected tab's stack — the pages that can be reached from several tabs.
    func push(_ route: Route) {
        switch tab {
        case .home: homePath.append(route)
        case .trends: trendsPath.append(route)
        case .food: foodPath.append(route)
        case .library: libraryPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    /// Set by Home's mic: Messages opens with the composer focused and dictation started; consumed once.
    var pendingDictation = false

    /// The morning check-in's end screen: a check-in on top of the selected stack steps aside for `route`, so Back returns
    /// to where the check-in was opened from, not into a finished check-in.
    func replaceCheckin(with route: Route) {
        switch tab {
        case .home: Self.swapCheckin(&homePath, with: route)
        case .trends: Self.swapCheckin(&trendsPath, with: route)
        case .food: Self.swapCheckin(&foodPath, with: route)
        case .library: Self.swapCheckin(&libraryPath, with: route)
        case .profile: Self.swapCheckin(&profilePath, with: route)
        }
    }

    private static func swapCheckin(_ path: inout [Route], with route: Route) {
        if let last = path.last, case .checkin = last { path.removeLast() }
        path.append(route)
    }

    /// Home's messages card: push Messages on the current stack (back returns to where the member was).
    func openMessages(dictate: Bool = false) {
        pendingDictation = dictate
        push(.messages)
    }

    /// From a message's "Find them in your library" and the Home nudge: the mini track, in the Library tab.
    func openSentTrack() {
        tab = .library
        libraryPath = [.sentTrack]
    }

    /// From a message's track card and the Library's Pathway cards: one personal track, in the Library tab.
    func openPersonalTrack(_ id: String) {
        tab = .library
        libraryPath = [.personalTrack(id)]
    }

    /// `functionalps://…` from a notification or a link: switch tab, then push.
    ///   checkin/<morning|midday|evening> · meal/<id>[?rate=1] · food · trends[/signal/<key>|/device/<key>|/patterns|/about/<signal|score>] · scores · action/<habitId> · supplements · supplement/<planId> · library[/<slug>] · library/show/<slug> · library/sent · library/track/<uuid> ·
    ///   bank[/<cardId>] · messages · careplan · documents · results[/<id>] · devices · settings · home · foundation (the track's day, on Home) ·
    ///   habit/<key> (a track habit's page) · foundation/summary (the approved day-7 summary) · foundation/day (the track's day, as its own page)
    func open(_ url: URL) {
        guard url.scheme == "functionalps" else { return }
        let parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        let rate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "rate" && $0.value == "1" } ?? false
        switch parts.first {
        case "checkin":
            tab = .home; homePath = []
            if let raw = parts.dropFirst().first, let slot = MomentSlot(rawValue: raw) { homePath.append(.checkin(slot)) }
            // `checkin/gut` still opens the standalone digestion screen (older pushes link to it);
            // in the app, digestion is answered inside the evening moment.
            else if parts.dropFirst().first == "gut" { homePath.append(.gutCheckin) }
        case "meal":
            tab = .food; foodPath = []
            if let id = parts.dropFirst().first { foodPath.append(.meal(id)); pendingRateMealId = rate ? id : nil }
        case "food":
            tab = .food; foodPath = []
            pendingCapture = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "capture" && $0.value == "1" } ?? false
        case "trends":
            // trends · trends/signal/<sleep|energy|focus|mood|stress|digestion> · trends/device/<apple_health|oura|…> · trends/patterns · trends/about/<signal|score>
            tab = .trends; trendsPath = []
            let rest = Array(parts.dropFirst())
            if rest.first == "signal", rest.count > 1, let signal = TrendSignal(rawValue: rest[1]) {
                trendsPath = [.trendSignal(signal)]
            } else if rest.first == "device", rest.count > 1, !rest[1].isEmpty {
                trendsPath = [.trendDevice(rest[1])]
            } else if rest.first == "patterns" {
                trendsPath = [.trendPatterns]
            } else if rest.first == "about", rest.count > 1, let key = SignalAboutKey(rawValue: rest[1]) {
                trendsPath = [.signalAbout(key.rawValue)]
            }
        case "scores": tab = .trends; trendsPath = [.scores]
        case "action":
            // action/<habitId> — one action of the plan, on its card (a reminder can open it).
            tab = .home; homePath = []
            if let id = parts.dropFirst().first, !id.isEmpty { homePath.append(.action(id)) }
        case "habit":
            // habit/<action key> — one Foundation Track habit's page.
            tab = .home; homePath = []
            if let key = parts.dropFirst().first, !key.isEmpty { homePath.append(.habit(key)) }
        case "supplements": tab = .home; homePath = []   // a supplement reminder's tap: Home, where today's list is
        case "supplement":
            // supplement/<planId> — one supplement's page.
            tab = .home; homePath = []
            if let id = parts.dropFirst().first, !id.isEmpty { homePath.append(.supplement(id)) }
        case "bank":
            // bank · bank/<cardId> — the foundation action bank, or one card in it.
            tab = .home; homePath = [.actionBank]
            if let id = parts.dropFirst().first, !id.isEmpty { homePath.append(.bankCard(id)) }
        case "library":
            // library · library/<slug> — the Library, or one article in it · library/show/<slug> — one show episode
            // (an experiment reminder lands there) · library/track/<uuid> — one personal mini track (an email link lands there).
            tab = .library; libraryPath = []
            let rest = Array(parts.dropFirst())
            if rest.first == "track" {
                // library/track/<uuid> — a personal mini track. A malformed id lands on the Library, never on a dead page.
                if rest.count > 1, Self.isTrackId(rest[1]) { libraryPath.append(.personalTrack(rest[1].lowercased())) }
            } else if rest.first == "sent" {
                // library/sent — the mini track of what the practice sent (a reply-with-resources push lands here).
                libraryPath.append(.sentTrack)
            } else if rest.first == "show" {
                // While the show is coming soon (`ShowFeature`), an episode link lands on the Library itself.
                if ShowFeature.episodesReachable(), rest.count > 1, !rest[1].isEmpty { libraryPath.append(.episode(rest[1])) }
            } else if let slug = rest.first, !slug.isEmpty {
                #if DEBUG
                // The showcase's video shot: the player, pushed as a tap on a Watch tile would.
                if Showcase.isOn, slug == "watch" { libraryPath.append(.libraryVideo(ShowcaseLibrary.video)) } else { libraryPath.append(.read(slug)) }
                #else
                libraryPath.append(.read(slug))
                #endif
            }
        case "profile": tab = .profile; profilePath = []
        case "messages": tab = .profile; profilePath = [.messages]
        case "careplan": tab = .profile; profilePath = [.carePlan]
        case "documents": tab = .profile; profilePath = [.documents]
        case "results":
            // results · results/<releaseId> — the "your results are ready" push lands on the release itself.
            tab = .profile; profilePath = [.labResults]
            if let id = parts.dropFirst().first, !id.isEmpty { profilePath.append(.labResult(id)) }
        case "devices": tab = .profile; profilePath = [.settings, .wearables]
        case "settings": tab = .profile; profilePath = [.settings]
        case "notifications": tab = .profile; profilePath = [.settings, .notifications]
        case "home": tab = .home; homePath = []
        case "foundation":
            tab = .home
            switch parts.dropFirst().first {
            case "summary": homePath = [.trackSummary]
            case "day": homePath = [.trackDay]
            default: homePath = []
            }
            #if DEBUG
            // The showcase screenshots only: a track action's card and the day's read, pushed over Home as a tap would.
            if Showcase.isOn, parts.count > 2 {
                if parts[1] == "card" { homePath = [.trackCard(parts[2], face: parts.count > 3 ? parts[3] : "standard")] }
                if parts[1] == "read" { homePath = [.read(parts[2])] }
            }
            #endif
        case "health": tab = .home; homePath = [.health]
        default: break   // e.g. wearables/callback — owned by the OAuth session, not a navigation
        }
    }

    /// A personal track id is a UUID; anything else is not a track link.
    nonisolated static func isTrackId(_ raw: String) -> Bool { UUID(uuidString: raw) != nil }

    /// The meal id a `meal/<id>` route names, nil otherwise.
    nonisolated static func mealId(from url: URL) -> String? {
        let parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        guard parts.first == "meal" else { return nil }
        return parts.dropFirst().first
    }

    /// Set by a `meal/<id>?rate=1` route; the meal page opens the reaction sheet and clears it.
    var pendingRateMealId: String?
    /// Set by `food?capture=1` (the onboarding's "Log my first meal"); the Food tab opens the photo chooser and clears it.
    var pendingCapture = false

    func pop() {
        switch tab {
        case .home: _ = homePath.popLast()
        case .trends: _ = trendsPath.popLast()
        case .food: _ = foodPath.popLast()
        case .library: _ = libraryPath.popLast()
        case .profile: _ = profilePath.popLast()
        }
    }

    /// The reader replaces the floating navbar with its own mark-done bar — on whichever tab it was opened
    /// (an article reached from Home or Profile too, not only from the Library).
    /// Set while the member types in a composer (Messages): the floating bar steps aside for the keyboard.
    var composing = false

    var hidesTabBar: Bool {
        if composing { return true }
        let top: Route? = switch tab {
        case .home: homePath.last
        case .trends: trendsPath.last
        case .food: foodPath.last
        case .library: libraryPath.last
        case .profile: profilePath.last
        }
        if case .read = top { return true }
        if case .libraryVideo = top { return true }
        return false
    }
}

/// Five stacks behind one floating glass pill (the system tab bar is hidden on every root).
struct MainTabView: View {
    /// The tabs the Foundation Track keeps locked for now (marked on the pill).
    private var lockedTabs: Set<AppRouter.Tab> {
        guard dependencies.track.status?.state == .active, dependencies.unlocks.phase == .known else { return [] }
        var tabs: Set<AppRouter.Tab> = []
        if !dependencies.unlocks.trendsOpen { tabs.insert(.trends) }
        if !dependencies.unlocks.foodOpen { tabs.insert(.food) }
        return tabs
    }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.homePath) {
                HomeView()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.home)

            NavigationStack(path: $router.trendsPath) {
                TrendsTabRoot()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.trends)

            NavigationStack(path: $router.foodPath) {
                FoodTabRoot()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.food)

            NavigationStack(path: $router.libraryPath) {
                LibraryView()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.library)

            NavigationStack(path: $router.profilePath) {
                ProfileView()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.profile)
        }
        .tint(FAColor.brand)
        .overlay(alignment: .bottom) {
            if !router.hidesTabBar {
                FloatingTabBar(selection: $router.tab, badges: [.library: router.libraryBadge], locked: lockedTabs)
                    .padding(.bottom, 2)
            }
        }
        .environment(router)
        // The Library badge: what the practice sent and the member has not opened. One small read on each tab
        // change and whenever the app comes forward; the screens that open an item decrement it at once.
        .task(id: router.tab) {
            router.libraryBadge = await dependencies.messaging.unopenedSentCount()
            await dependencies.unlocks.refresh()   // a check-in or a meal elsewhere may have opened Trends or Food
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { router.libraryBadge = await dependencies.messaging.unopenedSentCount() }
                Task { await dependencies.unlocks.refresh() }
                Task { await dependencies.supplements.load() }   // a new day's ticks, and its reminders
            }
        }
        // Notifications: taps and links land here; the badge clears whenever the app comes forward.
        .onOpenURL { router.open($0) }
        .onAppear {
            // The show is coming soon: drop any experiment reminder an internal tester scheduled on build 55.
            if ShowFeature.comingSoon { Task { await ShowReminders().cancelAll() } }
            AppDelegate.router = router
            AppDelegate.notifications = dependencies.notifications
            AppDelegate.supplements = dependencies.supplements
            if let url = AppDelegate.pendingRoute {
                AppDelegate.pendingRoute = nil
                Task { @MainActor in
                    await Task.yield()
                    router.open(url)
                }
            } else if let id = AppDelegate.pendingNotificationId {
                // A cold start from a push without a route: its row says where it belongs.
                AppDelegate.pendingNotificationId = nil
                let notifications = dependencies.notifications
                Task { @MainActor in
                    if let url = await notifications.route(forNotification: id) { router.open(url) }
                }
            }
            dependencies.notifications.clearBadge()
            // The member gate is through (this view only exists at `.ready`): start the Foundation Track's clock
            // (idempotent server-side) and read where the member stands — once per foreground.
            let track = dependencies.track
            Task { await track.foreground() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            dependencies.notifications.clearBadge()
            Task { await dependencies.notifications.refreshAuthorization() }
            let track = dependencies.track
            Task { await track.foreground() }
        }
    }

    private func destination(_ route: Route) -> some View {
        screen(route).faSwipeBack()
    }

    @ViewBuilder
    private func screen(_ route: Route) -> some View {
        switch route {
        case .profile: ProfileView()
        case .settings: SettingsView()
        case .meal(let id): MealDetailView(mealId: id)
        case .checkin(let slot): CheckinMomentView(slot: slot)
        case .track(let slug): TrackView(slug: slug)
        case .read(let slug): ReaderView(slug: slug)
        case .libraryDay(let day): LibraryDayView(day: day)
        case .libraryVideo(let video): LibraryVideoView(video: video)
        case .sentTrack: SentTrackView()
        case .personalTrack(let id): PersonalTrackView(trackId: id)
        case .episode(let slug): ShowEpisodeView(slug: slug)
        case .carePlan: CarePlanEntryView()
        case .clientObjective(let id): ClientObjectiveView(objectiveId: id)
        case .carePlanWhy: ClientWhyView()
        case .carePlanSituation: ClientSituationView()
        case .carePlanJourney: ClientJourneyView()
        case .carePlanFocus(let id): HabitDetailView(habitId: id, kind: .focus)
        case .carePlanAction(let id): HabitDetailView(habitId: id, kind: .action)
        case .action(let habitId): ActionCardView(source: .habit(habitId))
        case .supplement(let id): SupplementPage(supplementId: id)
        case .actionBank: ActionBankView()
        case .bankCard(let cardId): ActionCardView(source: .bankCard(cardId))
        case .trackCard(let cardId, let face): ActionCardView(source: .trackCard(cardId, face: face))
        case .habit(let key): HabitPageView(key: key)
        case .trackSummary: TrackSummaryView()
        case .trackDay: TrackDayPage()
        case .baseline: BaselineEditView()
        case .feedback: FeedbackView()
        case .guide: GuideView()
        case .guideChapter(let key): GuideChapterView(key: key)
        case .privacy: PrivacyView()
        case .consents: ConsentsView()
        case .viewData: ViewDataView()
        case .legal(let key): LegalDocumentView(key: key)
        case .messages: MessagesView()
        case .messagesAbout(let id, let name): MessagesView(initialContext: .meal(id: id), contextMealName: name)
        case .help: HelpView()
        case .wearables: WearablesView()
        case .health: HealthView()
        case .macros: MacrosDetailsView()
        case .nutritionTargets: NutritionTargetsView()
        case .micronutrients: MicronutrientsView()
        case .microGroup(let key): MicroGroupView(groupKey: key)
        case .microNutrient(let key): MicroNutrientView(nutrientKey: key)
        case .macro(let key): MacroDetailView(macroKey: key)
        case .notifications: NotificationsSettingsView()
        case .gutCheckin: GutCheckinView()
        case .gutIntelligence: GutIntelligenceView()
        case .scores: ScoresHubView()
        case .bodySignal(let s): SignalDetailView(kind: .body(s))
        case .gutSignal(let s): SignalDetailView(kind: .gut(s))
        case .labResults: LabResultsView()
        case .documents: DocumentsView()
        case .labResult(let id): LabResultView(releaseId: id)
        case .labMarker(let releaseId, let markerId): LabMarkerView(releaseId: releaseId, markerId: markerId)
        case .trendSignal(let signal): TrendSignalDetailView(signal: signal)
        case .trendDevice(let key): WearableSourceDetailView(deviceKey: key)
        case .trendPatterns: MemberPatternsView()
        case .signalAbout(let key): SignalAboutView(key: key)
        }
    }
}
