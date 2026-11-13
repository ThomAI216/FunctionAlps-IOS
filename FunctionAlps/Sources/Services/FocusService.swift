import Foundation
import Observation

/// Today's focus as one shared, observable value: the check-in screen asks for a recomputation, the Home card
/// shows the result, and neither needs to know about the other.
///
/// Loads are SERIALISED. Saving the morning check-in recomputes the day while returning to Home asks for it
/// again; if the plain read landed last it would put the pre-edit day back on screen. So a read waits for any
/// load already in flight, and a recomputation queues behind it rather than racing.
@MainActor
@Observable
final class FocusService {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded(TodayFocus)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// Today's kickoff morning routine as the table holds it (`patient_routine_runs`): offered when the green row is first shown,
    /// ticked step by step, finished with a moment. Nil until the row has been offered.
    private(set) var kickoffRun: KickoffRun?

    private let backend: any FunctionAlpsBackend
    private let auth: AuthService
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var inflight: Task<Void, Never>?
    private var generation = 0
    private var patientId: String?
    private var offering = false
    /// Writes of the run go one after the other, so a late step count never lands over the finish.
    private var writes: Task<Void, Never>?

    init(backend: any FunctionAlpsBackend, auth: AuthService, defaults: UserDefaults = .standard,
         now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.backend = backend
        self.auth = auth
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
    }

    /// The phone's clock for the routine's deadline (the showcase freezes it).
    var currentDate: Date { now() }

    /// The kickoff morning routine was finished today: the green row on Home is ticked.
    var kickoffDone: Bool { kickoffRun?.completedAt != nil }

    // MARK: The kickoff routine's run

    /// The green row is on screen: make sure the day has its row. The table is the source; a copy kept on this phone covers a write
    /// that failed (or a database without the table yet). Fails soft: the walk never depends on any of it.
    /// `wake` is asked only when the deadline has to be worked out (a day with no run yet): the check-in's wake time, else the wearable's.
    func offerKickoff(patientId: String, wake: @MainActor () async -> String?) async {
        guard let day = focus?.day, kickoffRun?.day != day, !offering else { return }
        offering = true
        defer { offering = false }
        self.patientId = patientId
        var remoteReadable = true
        do {
            if let existing = try await backend.kickoffRun(patientId: patientId, day: day) {
                adopt(existing)
                // A finish whose write failed earlier (kept on this phone) is sent again.
                if existing.completedAt == nil, let local = localRun(day: day), local.completedAt != nil {
                    var merged = existing
                    merged.completedAt = local.completedAt
                    merged.stepsDone = max(existing.stepsDone, local.stepsDone)
                    adopt(merged)
                    let snapshot = merged
                    enqueue { [weak self] in await self?.write(KickoffRunLogic.completionColumns(snapshot, patientId: patientId), context: "focus.kickoff.finish") }
                }
                return
            }
        } catch {
            remoteReadable = false
            if let appError = error as? AppError {
                Log.error(appError, in: Log.data, context: "focus.kickoff.read")
                if case .unauthorized = appError { await auth.handleUnauthorized(); return }
            }
        }
        let run: KickoffRun
        if let local = localRun(day: day) {
            run = local
        } else {
            let wakeTime = await wake()
            run = KickoffRun(day: day, focusCell: focus?.cell?.id, offeredAt: now(),
                             dueAt: KickoffDeadline.dueAt(day: day, wakeTime: wakeTime, calendar: calendar), completedAt: nil, stepsDone: 0)
        }
        adopt(run)
        // A read that failed may be hiding a finished row: never write the offer over it.
        guard remoteReadable else { return }
        let offer = run
        enqueue { [weak self] in await self?.write(KickoffRunLogic.offerColumns(offer, patientId: patientId), context: "focus.kickoff.offer") }
    }

    /// A step was ticked (or the walk went back): the count the clinic sees. Never lowered once reached.
    func kickoffSteps(_ count: Int) {
        guard var run = kickoffRun, let patientId, run.completedAt == nil, count > run.stepsDone else { return }
        run.stepsDone = min(count, KickoffRun.maxSteps)
        adopt(run)
        let snapshot = run
        enqueue { [weak self] in await self?.write(KickoffRunLogic.progressColumns(snapshot, patientId: patientId), context: "focus.kickoff.steps") }
    }

    /// The walk reached its end: the row is ticked at once and the moment written behind. The first finish counts; a second walk
    /// the same day does not move it.
    func finishKickoff(steps: Int) {
        guard var run = kickoffRun, let patientId, run.completedAt == nil else { return }
        run.stepsDone = min(max(steps, run.stepsDone), KickoffRun.maxSteps)
        run.completedAt = now()
        adopt(run)
        let snapshot = run
        enqueue { [weak self] in await self?.write(KickoffRunLogic.completionColumns(snapshot, patientId: patientId), context: "focus.kickoff.finish") }
    }

    /// Waits for the writes queued so far (the tests; nothing else needs to).
    func settleWrites() async { await writes?.value }

    private func adopt(_ run: KickoffRun) {
        kickoffRun = run
        saveLocal(run)
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = writes
        writes = Task { await previous?.value; await work() }
    }

    private func write(_ columns: ColumnPatch, context: StaticString) async {
        guard let patientId else { return }
        do {
            try await backend.saveKickoffRun(patientId: patientId, columns: columns)
        } catch {
            if let appError = error as? AppError {
                Log.error(appError, in: Log.data, context: context)
                if case .unauthorized = appError { await auth.handleUnauthorized() }
            }
        }
    }

    // The copy on this phone. The showcase never reads or writes it (a screenshot must not inherit the last one).
    private var usesLocalCopy: Bool {
        #if DEBUG
        return !Showcase.isOn
        #else
        return true
        #endif
    }

    private func localRun(day: String) -> KickoffRun? {
        guard usesLocalCopy, let data = defaults.data(forKey: KickoffRowLogic.localRunKey),
              let run = try? JSONDecoder().decode(KickoffRun.self, from: data), run.day == day else { return nil }
        return run
    }

    private func saveLocal(_ run: KickoffRun) {
        guard usesLocalCopy, let data = try? JSONEncoder().encode(run) else { return }
        defaults.set(data, forKey: KickoffRowLogic.localRunKey)
    }

    var focus: TodayFocus? {
        if case .loaded(let f) = phase { return f }
        return nil
    }

    /// Reads today's focus (computing it the first time the morning allows). `recompute` after the morning
    /// check-in is saved or edited, so a changed morning retires what no longer fits.
    func load(recompute: Bool = false) async {
        if let running = inflight, !recompute { await running.value; return }
        let previous = inflight
        generation += 1
        let mine = generation
        let task = Task { [weak self] in
            await previous?.value
            await self?.fetch(recompute: recompute)
        }
        inflight = task
        await task.value
        if generation == mine { inflight = nil }
    }

    private func fetch(recompute: Bool) async {
        // Keep what is on screen while refreshing; only a first load shows the spinner.
        if focus == nil { phase = .loading }
        do {
            phase = .loaded(try await backend.dailyFocus(recompute: recompute, locale: TodayFocus.locale()))
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "focus.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if focus == nil { phase = .failed(error.userMessage) }
        } catch {
            if focus == nil { phase = .failed(String(describing: error)) }
        }
    }

    /// Done, or undone. Shown at once and written behind; a failed write puts it back as it was.
    func setCompleted(_ offer: FocusOffer, _ completed: Bool) async {
        guard case .loaded(let current) = phase, let i = current.offers.firstIndex(where: { $0.id == offer.id }) else { return }
        var offers = current.offers
        offers[i].completed = completed
        if completed { offers[i].accepted = true }
        phase = .loaded(current.replacing(offers: offers))
        do {
            try await backend.setFocusOfferCompleted(id: offer.id, completed: completed)
        } catch {
            if case .loaded(let now) = phase, let j = now.offers.firstIndex(where: { $0.id == offer.id }) {
                var back = now.offers
                back[j] = offer
                phase = .loaded(now.replacing(offers: back))
            }
            if let appError = error as? AppError {
                Log.error(appError, in: Log.data, context: "focus.done")
                if case .unauthorized = appError { await auth.handleUnauthorized() }
            }
        }
    }
}
