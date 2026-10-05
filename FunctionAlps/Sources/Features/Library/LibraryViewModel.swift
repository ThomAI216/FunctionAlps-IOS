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
            case .priority: String(localized: "library.section.priority", defaultValue: "Priority")
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

    private let library: LibraryService
    private let members: MemberService
    private let shows: ShowService
    private let reminders = ShowReminders()

    init(library: LibraryService, members: MemberService, shows: ShowService) {
        self.library = library
        self.members = members
        self.shows = shows
    }

    func load() async {
        defer {
            loaded = true
            if show == nil && active == .show { active = .priority }
        }
        guard let member = try? await members.currentMember() else { bundle = LibraryDemo.bundle; show = nil; return }
        patientId = member.patientId
        // The show reads in parallel and fails on its own: the catalog never waits on CLINICAL.
        let shows = self.shows, pid = member.patientId
        async let showState = shows.libraryState(patientId: pid)
        bundle = await library.bundle(patientId: member.patientId) ?? LibraryDemo.bundle
        covers = await library.topicCovers()
        show = await showState
    }

    /// The Continue row's check: today's experiment day, under the same rules as the episode page.
    func markToday(_ row: ShowExperimentRow) async {
        guard let patientId, row.canMarkToday, let day = row.state.nextDay, markingSlug == nil else { return }
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
        let plan = updated.map { ShowLogic.reminderPlan(days: $0.days.map(\.day), state: $0.state, now: shows.now, calendar: .current) } ?? []
        let items = plan.map { p in
            ShowReminders.Item(day: p.day, fireAt: p.fireAt, title: title,
                               body: "\(String(localized: "show.dayN", defaultValue: "Day \(p.day)")) · \(actions[p.day] ?? "")")
        }
        await reminders.apply(slug: row.slug, items: items)
    }

    func toggle(_ section: Section) {
        if expanded.contains(section) { expanded.remove(section) } else { expanded.insert(section) }
    }

    var priority: [TrackWithProgress] { bundle.prioritySlugs.compactMap { s in bundle.tracks.first { $0.slug == s } } }
    var inProgress: [TrackWithProgress] { bundle.tracks.filter { $0.state == .inProgress } }
    var foundations: [LibResource] { bundle.resources.filter { !$0.supplement } }
    var supplements: [LibResource] { bundle.resources.filter(\.supplement) }
    var doneTotal: Int { bundle.tracks.reduce(0) { $0 + $1.done } }
    var lessonTotal: Int { bundle.tracks.reduce(0) { $0 + $1.total } }
    var pct: Double { lessonTotal == 0 ? 0 : Double(doneTotal) / Double(lessonTotal) }
    var week: Int? { library.weekNumber(startDate: bundle.plan?.startDate) }

    func count(_ section: Section) -> Int? {
        switch section {
        case .tracks: bundle.tracks.count
        case .foundations: foundations.count
        case .supplements: supplements.count
        case .show: show.flatMap { $0.snapshot.thisWeek.isEmpty ? nil : $0.snapshot.thisWeek.count }
        case .priority: nil
        }
    }
}
