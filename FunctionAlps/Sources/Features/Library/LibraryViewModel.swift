import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    enum Section: String, CaseIterable, Identifiable {
        case show, priority, tracks, foundations, supplements
        var id: String { rawValue }
        var title: String {
            switch self {
            case .show: String(localized: "show.navGroup", defaultValue: "The show")
            // Owner, 2026-11-05: "put 'your personalized track' instead of the priority" — one section, the Pathway
            // (what the practice sent) and the practitioner's priority tracks together.
            case .priority: PathwayCopy.title
            case .tracks: String(localized: "library.section.tracks", defaultValue: "Tracks")
            case .foundations: String(localized: "library.section.foundations", defaultValue: "Foundations")
            case .supplements: String(localized: "library.section.supplements", defaultValue: "Supplements")
            }
        }
    }

    private(set) var bundle: LibraryBundle = LibraryDemo.bundle
    private(set) var loaded = false
    var active: Section = .show
    /// The show (CLINICAL library API + this member's experiments); nil = no show data → the section hides.
    private(set) var show: ShowLibraryState?
    private(set) var covers: [String: URL] = [:]
    private(set) var markingSlug: String?
    var expanded: Set<Section> = []
    private(set) var patientId: String?
    /// What the practice sent with messages (CLINICAL migration 277), newest first, one card per item.
    private(set) var sent: [MessageResource] = []
    /// The personal mini tracks (CLINICAL migration 283), newest first, and the slugs already opened.
    private(set) var personal: [PersonalTrack] = []
    private(set) var openedSlugs: Set<String> = []

    private let library: LibraryService
    private let members: MemberService
    private let shows: ShowService
    private let messaging: MessagingService?
    private let reminders = ShowReminders()

    init(library: LibraryService, members: MemberService, shows: ShowService, messaging: MessagingService? = nil) {
        self.library = library
        self.members = members
        self.shows = shows
        self.messaging = messaging
    }

    func load() async {
        defer {
            loaded = true
            if showPresentation != .live && active == .show { active = .priority }
        }
        guard let member = try? await members.currentMember() else { bundle = LibraryDemo.bundle; show = nil; return }
        patientId = member.patientId
        // The practice's sends ride their own read and fail soft to none: the catalog never waits on them.
        if let messaging {
            async let sentRows = messaging.sentResources()
            async let trackRows = messaging.personalTracks()
            async let opened = messaging.openedSlugs()
            sent = await sentRows
            personal = await trackRows
            openedSlugs = await opened
        }
        // Coming soon (owner, 2026-10-06): the show is a blurred preview — nothing is read from CLINICAL.
        if shows.comingSoon {
            show = nil
            bundle = await library.bundle(patientId: member.patientId) ?? LibraryDemo.bundle
            covers = await library.topicCovers()
            return
        }
        // The show reads in parallel and fails on its own: the catalog never waits on CLINICAL.
        let shows = self.shows, pid = member.patientId
        async let showState = shows.libraryState(patientId: pid)
        bundle = await library.bundle(patientId: member.patientId) ?? LibraryDemo.bundle
        covers = await library.topicCovers()
        show = await showState
    }

    /// The Continue row's check: today's experiment day, under the same rules as the episode page.
    func markToday(_ row: ShowExperimentRow) async {
        guard !shows.comingSoon, let patientId, row.canMarkToday, let day = row.state.nextDay, markingSlug == nil else { return }
        markingSlug = row.slug
        defer { markingSlug = nil }
        _ = await shows.markDay(patientId: patientId, slug: row.slug, day: day, dayNumbers: row.days.map(\.day))
        if let fresh = await shows.libraryState(patientId: patientId) { show = fresh }
        // A reminder set on the episode page follows the progress (today's goes once today is done; a finished
        // week drops out of Continue and takes its reminders with it).
        guard await reminders.isOn(slug: row.slug) else { return }
        let updated = show?.experiments.first { $0.slug == row.slug }
        let actions = Dictionary((updated?.days ?? []).map { ($0.day, $0.action) }, uniquingKeysWith: { first, _ in first })
        let title = String(localized: "show.experimentTitle", defaultValue: "Your one-week experiment")
        let plan = updated.map { ShowFeature.reminderPlan(comingSoon: shows.comingSoon, days: $0.days.map(\.day), state: $0.state, now: shows.now, calendar: .current) } ?? []
        let items = plan.map { p in
            ShowReminders.Item(day: p.day, fireAt: p.fireAt, title: title,
                               body: "\(String(localized: "show.dayN", defaultValue: "Day \(p.day)")) · \(actions[p.day] ?? "")")
        }
        await reminders.apply(slug: row.slug, items: items)
    }

    /// Live, hidden (no data), or the coming-soon preview (`ShowFeature`).
    var showPresentation: ShowFeature.Presentation {
        ShowFeature.presentation(comingSoon: shows.comingSoon, hasData: show != nil)
    }

    func toggle(_ section: Section) {
        if expanded.contains(section) { expanded.remove(section) } else { expanded.insert(section) }
    }

    var priority: [TrackWithProgress] { bundle.prioritySlugs.compactMap { s in bundle.tracks.first { $0.slug == s } } }
    var inProgress: [TrackWithProgress] { bundle.tracks.filter { $0.state == .inProgress } }
    var foundations: [LibResource] { bundle.resources.filter { !$0.supplement } }
    /// The supplements LIST: pages only; use rows group under their page (`supplementUses`).
    var supplements: [LibResource] { SupplementLogic.pages(bundle.resources) }
    var supplementUses: [String: [LibResource]] { SupplementLogic.usesByPage(bundle.resources) }
    var doneTotal: Int { bundle.tracks.reduce(0) { $0 + $1.done } }
    var lessonTotal: Int { bundle.tracks.reduce(0) { $0 + $1.total } }
    var pct: Double { lessonTotal == 0 ? 0 : Double(doneTotal) / Double(lessonTotal) }
    var week: Int? { library.weekNumber(startDate: bundle.plan?.startDate) }

    private var pathwayCount: Int { (sent.isEmpty ? 0 : 1) + personal.count + priority.count }

    func count(_ section: Section) -> Int? {
        switch section {
        case .tracks: bundle.tracks.count
        case .foundations: foundations.count
        case .supplements: supplements.count
        case .show: showPresentation == .live ? show.flatMap { $0.snapshot.thisWeek.isEmpty ? nil : $0.snapshot.thisWeek.count } : nil
        case .priority: pathwayCount == 0 ? nil : pathwayCount
        }
    }
}
