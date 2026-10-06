import Foundation

/// "The FunctionAlps Show" inside the Library: the list and the episodes from the CLINICAL library API, the member's
/// one-week experiment progress in `member_lesson_progress` (the members web's exact rows: track_id null,
/// `show:<slug>:day:<n>`, same RLS self-insert). Everything fails soft: no show data hides the show section and
/// leaves every other Library section as it was.
struct ShowService: Sendable {
    enum EpisodeResult: Sendable, Equatable {
        case ok(ShowEpisode)
        case notFound
        case error
    }

    enum MarkOutcome: Sendable, Equatable {
        case ok
        /// Not the day to mark (an earlier day is open, or a day was already marked today): the screen was stale.
        case notAllowed
        case error
    }

    private let backend: any FunctionAlpsBackend
    private let clock: @Sendable () -> Date
    /// `ShowFeature.comingSoon`: the service goes inert — no CLINICAL call, no progress read, no write.
    let comingSoon: Bool

    init(backend: any FunctionAlpsBackend, now: @escaping @Sendable () -> Date = { ShowService.defaultNow() },
         comingSoon: Bool = ShowFeature.comingSoon) {
        self.backend = backend
        self.clock = now
        self.comingSoon = comingSoon
    }

    /// The real clock — except in the Debug showcase, which is set in the show's first week (Friday 9 Oct 2026).
    static func defaultNow() -> Date {
        #if DEBUG
        if Showcase.isOn { return ShowcaseData.showNow }
        #endif
        return Date()
    }

    var now: Date { clock() }
    /// Today in the show's zone — the calendar day the one-mark-a-day rule counts in.
    var today: String { ShowLogic.zonedDay(now) }

    // MARK: Reads

    func library() async -> ShowLibrary? {
        guard !comingSoon else { return nil }
        do { return try await backend.showLibrary() } catch {
            Log.data.error("show.library: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func episode(slug: String) async -> EpisodeResult {
        guard !comingSoon, ShowLogic.isSlug(slug) else { return .notFound }
        do {
            guard let episode = try await backend.showEpisode(slug: slug) else { return .notFound }
            return .ok(episode)
        } catch {
            Log.data.error("show.episode: \(String(describing: error), privacy: .public)")
            return .error
        }
    }

    /// Every experiment mark of this member, by episode slug. Fail-soft: [:].
    func marks(patientId: String) async -> [String: [ShowLogic.ExperimentMark]] {
        (try? await strictMarks(patientId: patientId)) ?? [:]
    }

    private func strictMarks(patientId: String) async throws -> [String: [ShowLogic.ExperimentMark]] {
        guard !comingSoon else { return [:] }
        return ShowLogic.marks(from: try await backend.showProgress(patientId: patientId))
    }

    /// The Library's show section in one go; nil = no show data.
    func libraryState(patientId: String) async -> ShowLibraryState? {
        guard let library = await library() else { return nil }
        let marks = await marks(patientId: patientId)
        let snapshot = ShowSnapshot.build(library, marks: marks, now: now)
        let rows = await experimentRows(snapshot.experiments, today: snapshot.today)
        return ShowLibraryState(library: library, snapshot: snapshot, experiments: rows)
    }

    /// The three most recent experiments, with their guide days (one episode read each, in parallel); the finished
    /// ones are left out. An episode that cannot be read still shows its progress, without the mark button.
    private func experimentRows(_ experiments: [ShowSnapshot.Experiment], today: String) async -> [ShowExperimentRow] {
        let picked = Array(experiments.prefix(3))
        let lang = ShowFormat.lang
        let guides = await withTaskGroup(of: (Int, [ShowGuide.Day]).self, returning: [Int: [ShowGuide.Day]].self) { group in
            for (i, x) in picked.enumerated() {
                group.addTask {
                    if case .ok(let loaded) = await self.episode(slug: x.slug) {
                        return (i, loaded.guide?.pick(lang).experiment.days ?? [])
                    }
                    return (i, [])
                }
            }
            var out: [Int: [ShowGuide.Day]] = [:]
            for await (i, days) in group { out[i] = days }
            return out
        }
        return picked.enumerated().compactMap { (i, x) -> ShowExperimentRow? in
            let days = guides[i] ?? []
            let numbers = days.isEmpty ? Array(1...7) : days.map(\.day)
            let state = ShowLogic.experimentState(x.marks, dayNumbers: numbers, today: today)
            guard state.nextDay != nil else { return nil }
            return ShowExperimentRow(slug: x.slug, card: x.card, days: days, state: state)
        }
    }

    // MARK: Write

    /// Mark one experiment day done — the members web's `markExperimentDay`, client-side: the day must exist in the
    /// guide, days go in order, one per Zurich calendar day. Re-reads the marks first (another device may have
    /// marked since the screen loaded). A duplicate row (unique index, 23505) already means done.
    func markDay(patientId: String, slug: String, day: Int, dayNumbers: [Int]) async -> MarkOutcome {
        guard !comingSoon, ShowLogic.isSlug(slug), dayNumbers.contains(day) else { return .notAllowed }
        let current: [ShowLogic.ExperimentMark]
        do { current = try await strictMarks(patientId: patientId)[slug] ?? [] } catch {
            Log.data.error("show.mark.read: \(String(describing: error), privacy: .public)")
            return .error
        }
        if current.contains(where: { $0.day == day }) { return .ok }
        let state = ShowLogic.experimentState(current, dayNumbers: dayNumbers, today: today)
        guard ShowLogic.canMark(state, day: day) else { return .notAllowed }
        do {
            try await backend.insertLessonProgress(patientId: patientId, trackId: nil, contentSlug: ShowLogic.experimentKey(slug: slug, day: day))
            return .ok
        } catch AppError.validation(let message) where message.contains("23505") || message.lowercased().contains("duplicate") {
            return .ok
        } catch {
            Log.data.error("show.mark: \(String(describing: error), privacy: .public)")
            return .error
        }
    }
}
