import Foundation

/// What the Library's show section renders — pure, built from the validated list, the member's experiment marks and
/// `now` (the members web `src/lib/show/view.ts`). Views never compute "today" or the next live themselves.
struct ShowSnapshot: Sendable, Equatable {
    enum LiveWhen: Sendable, Equatable { case now, today, tomorrow, later }

    struct Live: Sendable, Equatable, Identifiable {
        /// The published event's slug; nil = from the schedule only.
        let slug: String?
        let title: ShowText?
        let start: Date
        let end: Date
        let when: LiveWhen
        var id: Date { start }
    }

    struct WeekDay: Sendable, Equatable, Identifiable {
        let day: String
        let kind: ShowKind
        let track: ShowTrack
        let start: Date
        let isToday: Bool
        /// The published replay of that day, if any.
        let episode: ShowEpisodeCard?
        /// The published upcoming event of that day, if any.
        let upcoming: ShowUpcoming?
        var id: String { day }
    }

    struct Experiment: Sendable, Equatable, Identifiable {
        let slug: String
        let card: ShowEpisodeCard?
        let marks: [ShowLogic.ExperimentMark]
        var id: String { slug }
    }

    let time: String
    let preLaunch: Bool
    /// Today in the show's zone ("YYYY-MM-DD").
    let today: String
    let nextLive: Live?
    /// Up to four lives: the published ones, else the schedule's next ones.
    let lives: [Live]
    let monday: String
    let days: [WeekDay]
    /// Replays of the presented week, newest first.
    let thisWeek: [ShowEpisodeCard]
    let all: [ShowEpisodeCard]
    /// Episodes with at least one experiment mark, most recently marked first.
    let experiments: [Experiment]

    static func build(_ lib: ShowLibrary, marks: [String: [ShowLogic.ExperimentMark]], now: Date) -> ShowSnapshot {
        let clock = lib.clock
        let tz = clock.timezone
        let today = ShowLogic.zonedDay(now, timeZone: tz)

        func when(_ start: Date, _ end: Date) -> LiveWhen {
            if start <= now && now < end { return .now }
            let day = ShowLogic.zonedDay(start, timeZone: tz)
            if day == today { return .today }
            if day == ShowLogic.addDays(today, 1) { return .tomorrow }
            return .later
        }

        // Lives: the published upcoming lives first (they carry the website page) …
        var lives = lib.upcoming
            .filter { $0.kind == .live && $0.endsAt > now }
            .prefix(4)
            .map { Live(slug: $0.slug, title: $0.title, start: $0.startsAt, end: $0.endsAt, when: when($0.startsAt, $0.endsAt)) }
        // … else the schedule's next few, never before the launch.
        if lives.isEmpty {
            var cursor = now
            for _ in 0..<4 {
                guard let occ = ShowLogic.nextLive(clock: clock, now: cursor) else { break }
                lives.append(Live(slug: nil, title: nil, start: occ.start, end: occ.end, when: when(occ.start, occ.end)))
                cursor = occ.end.addingTimeInterval(60)
            }
        }
        lives.sort { $0.start < $1.start }

        let week = ShowLogic.week(clock: clock, now: now)
        let days = week.days.map { occ in
            WeekDay(
                day: occ.day, kind: occ.slot.kind, track: occ.slot.track, start: occ.start, isToday: occ.day == today,
                episode: lib.episodes.first { ShowLogic.zonedDay($0.startsAt, timeZone: tz) == occ.day },
                upcoming: lib.upcoming.first { ShowLogic.zonedDay($0.startsAt, timeZone: tz) == occ.day }
            )
        }

        let bySlug = Dictionary(lib.episodes.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        func lastMark(_ m: [ShowLogic.ExperimentMark]) -> String { m.map(\.zurichDay).max() ?? "" }
        let experiments = marks
            .filter { !$0.value.isEmpty }
            .sorted { a, b in
                let la = lastMark(a.value), lb = lastMark(b.value)
                return la == lb ? a.key < b.key : la > lb
            }
            .map { Experiment(slug: $0.key, card: bySlug[$0.key], marks: $0.value) }

        return ShowSnapshot(
            time: clock.time, preLaunch: week.preLaunch, today: today, nextLive: lives.first, lives: lives,
            monday: week.monday, days: days,
            thisWeek: lib.episodes.filter { ShowLogic.inWeek($0.startsAt, monday: week.monday, timeZone: tz) },
            all: lib.episodes, experiments: experiments
        )
    }
}

/// One experiment in progress, as the Library's Continue row shows it.
struct ShowExperimentRow: Sendable, Equatable, Identifiable {
    let slug: String
    let card: ShowEpisodeCard?
    /// The guide's days (empty when the episode could not be read: the row then only shows progress).
    let days: [ShowGuide.Day]
    let state: ShowLogic.ExperimentState
    var id: String { slug }

    /// Seven when the guide is unknown — the show's experiments run a week.
    var total: Int { days.isEmpty ? 7 : days.count }
    /// The day being worked on (the next one, or the last when all are done).
    var current: Int { state.nextDay ?? total }
    var action: String? { days.first { $0.day == state.nextDay }?.action }
    var canMarkToday: Bool {
        guard let next = state.nextDay, !days.isEmpty else { return false }
        return ShowLogic.canMark(state, day: next)
    }
}

/// Everything the Library's show section needs, loaded in one go (nil = no show data: the section hides).
struct ShowLibraryState: Sendable, Equatable {
    let library: ShowLibrary
    let snapshot: ShowSnapshot
    /// Experiments in progress (at least one day done, not finished), most recent first.
    let experiments: [ShowExperimentRow]
}
