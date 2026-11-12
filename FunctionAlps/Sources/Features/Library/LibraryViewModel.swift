import Foundation
import Observation

/// The Library tab: the Foundation Track day by day, the reads tied to the member's habits, the videos, search —
/// and, below them, whatever the practice prescribed (personal tracks, what it sent, priority tracks).
/// The track and the habits are the app's shared services; this model only reads them (so the tab follows them)
/// and keeps the catalog read.
@MainActor
@Observable
final class LibraryViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
        case unauthorized
    }

    enum Anchor: String { case forYou, track, watch }

    private(set) var phase: Phase = .loading
    private(set) var catalog: LibraryCatalog?
    private(set) var patientId: String?
    /// What the practice sent with messages (CLINICAL migration 277), newest first, one card per item.
    private(set) var sent: [MessageResource] = []
    /// The personal mini tracks (CLINICAL migration 283), newest first, and the slugs already opened.
    private(set) var personal: [PersonalTrack] = []
    private(set) var openedSlugs: Set<String> = []
    var query = ""
    var anchor: Anchor = .forYou

    private let library: LibraryService
    private let members: MemberService
    private let track: TrackService
    private let habits: HabitsService
    private let messaging: MessagingService?

    init(library: LibraryService, members: MemberService, track: TrackService, habits: HabitsService, messaging: MessagingService? = nil) {
        self.library = library
        self.members = members
        self.track = track
        self.habits = habits
        self.messaging = messaging
        #if DEBUG
        if Showcase.screen == .librarySearch { query = ShowcaseLibrary.query }
        #endif
    }

    // MARK: Loading

    func load() async {
        if catalog == nil { phase = .loading }
        let member: Member
        do {
            member = try await members.currentMember()
        } catch AppError.unauthorized {
            phase = .unauthorized
            return
        } catch {
            if catalog == nil { phase = .failed(Self.message(error)) }
            return
        }
        patientId = member.patientId
        async let trackRead: Void = track.foreground()
        // The practice's sends ride their own read and fail soft to none: the catalog never waits on them.
        if let messaging {
            async let sentRows = messaging.sentResources()
            async let trackRows = messaging.personalTracks()
            async let opened = messaging.openedSlugs()
            sent = await sentRows
            personal = await trackRows
            openedSlugs = await opened
        }
        do {
            catalog = try await library.catalog(patientId: member.patientId)
            phase = .loaded
        } catch AppError.unauthorized {
            phase = .unauthorized
        } catch {
            if catalog == nil { phase = .failed(Self.message(error)) }
        }
        await trackRead
        // The member's habits (Practice it, search, the reads tied to them): Home loads them first in a normal run.
        if habits.plan == nil { await habits.load(patientId: member.patientId, day: ISO8601.dayString(Date())) }
    }

    /// After the reader: which reads the member has read now (cheap, one read).
    func refreshRead() async {
        guard phase == .loaded, let patientId, let slugs = await library.readSlugs(patientId: patientId) else { return }
        catalog?.readSlugs = slugs
        openedSlugs = slugs
    }

    private static func message(_ error: any Error) -> String {
        (error as? AppError)?.userMessage ?? (error as? LocalizedError)?.errorDescription
            ?? String(localized: "library.error.generic", defaultValue: "Something went wrong.")
    }

    // MARK: The Foundation Track

    var articles: [LibraryArticle] { catalog?.articles ?? [] }
    var readSlugs: Set<String> { catalog?.readSlugs ?? [] }
    var bundle: LibraryBundle? { catalog?.bundle }

    /// The member's track day while they are on the track; nil otherwise (every day open).
    var today: Int? { FoundationLibraryLogic.currentDay(track.status) }

    private var through: Int? { FoundationLibraryLogic.actionsThrough(status: track.status) }

    var dayGroups: [LibraryDayGroup] {
        let primary = Dictionary(track.days.compactMap { day in day.readSlug.map { (day.day, $0) } }, uniquingKeysWith: { first, _ in first })
        return FoundationLibraryLogic.dayGroups(articles: articles, today: today, readSlugs: readSlugs, primary: primary)
    }

    var readTotals: (read: Int, total: Int) { FoundationLibraryLogic.readTotals(dayGroups) }

    /// The title the track gives a day ("Your mind, day to day") for the soft-lock sheet's eyebrow.
    func dayTitle(_ day: Int) -> String? {
        track.days.first { $0.day == day }.flatMap { TrackLogic.text($0.titleEn, $0.titleFr, locale: track.locale) }
    }

    // MARK: For your habits · Watch

    var habitReads: [LibraryHabitRead] {
        var sources: [FoundationLibraryLogic.HabitReadSource] = []
        if today != nil, let day = track.today {
            for action in day.actions where !action.reads.isEmpty {
                let card = action.habitBankId.flatMap { track.cards[$0] }
                sources.append(.init(habitTitle: TrackLogic.actionTitle(action, card: card, locale: track.locale), slugs: action.reads))
            }
        }
        for habit in habits.plan?.activeHabits ?? [] {
            let slugs = FoundationLibraryLogic.articleSlugs(of: habit.habitBankId.flatMap { habits.plan?.cards[$0] })
            if !slugs.isEmpty { sources.append(.init(habitTitle: habit.title, slugs: slugs)) }
        }
        return FoundationLibraryLogic.forYourHabits(sources: sources, articles: articles, today: today)
    }

    var videos: [LibraryVideo] {
        var sources: [FoundationLibraryLogic.VideoSource] = []
        for (_, action) in FoundationLibraryLogic.trackActions(days: track.days, through: through) {
            guard let id = action.habitBankId, let card = track.cards[id] else { continue }
            sources.append(.init(cardId: id, cardTitle: TrackLogic.actionTitle(action, card: card, locale: track.locale), links: ActionCardLogic.links(card.resources)))
        }
        for habit in habits.plan?.activeHabits ?? [] {
            let card = habit.habitBankId.flatMap { habits.plan?.cards[$0] }
            sources.append(.init(cardId: habit.habitBankId, cardTitle: habit.title,
                                 links: ActionCardLogic.links(card?.resources) + ActionCardLogic.habitLinks(habit.resources)))
        }
        return FoundationLibraryLogic.videos(from: sources)
    }

    // MARK: Search

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var memberHabits: [LibraryHabit] {
        FoundationLibraryLogic.habits(plan: habits.plan, days: track.days, through: through, cards: track.cards, locale: track.locale)
    }

    var searchResults: LibrarySearch.Results {
        LibrarySearch.results(query: query, articles: articles, habits: memberHabits, videos: videos)
    }

    // MARK: What the practice prescribed (kept below the new sections)

    var priority: [TrackWithProgress] { bundle.map { b in b.prioritySlugs.compactMap { s in b.tracks.first { $0.slug == s } } } ?? [] }
    /// "Continue" is for the practitioner's priority tracks the member has started — the generic tracks grid is gone.
    var continuing: [TrackWithProgress] { priority.filter { $0.state == .inProgress } }
    var hasPrescribed: Bool { !sent.isEmpty || !personal.isEmpty || !priority.isEmpty }
}
