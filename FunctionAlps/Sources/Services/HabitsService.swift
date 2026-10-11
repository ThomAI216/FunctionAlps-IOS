import Foundation
import Observation

/// The Habit Loop's day as one shared, observable value: the clinician's habits, which are done, and the
/// check-off. Loads once per fresh Today (Home asks); a check-off is shown at once and written behind, and put
/// back as it was if the write fails. After a check-off the server's gate evaluator is poked fire-and-forget —
/// a newly reached, clinician-pre-authorised step unlocks without waiting for the nightly sweep, and a failed
/// poke costs nothing (the sweep catches it).
@MainActor
@Observable
final class HabitsService {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded(HabitPlan)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let backend: any FunctionAlpsBackend
    private let auth: AuthService
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    /// The last day asked for — what a retry reloads.
    private var request: (patientId: String, day: String)?

    init(backend: any FunctionAlpsBackend, auth: AuthService, now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.backend = backend
        self.auth = auth
        self.now = now
        self.calendar = calendar
    }

    var plan: HabitPlan? {
        if case .loaded(let p) = phase { return p }
        return nil
    }

    /// The patient-local hour — which moment of the day the card leads with.
    var hour: Int { calendar.component(.hour, from: now()) }

    /// Today's habits in the order the card shows them, each on the face the day's band calls for
    /// (see `HabitEngine.todayActions`). The band is the focus service's — the server's one read of the day.
    func actions(band: ReadinessBand?) -> [HabitAction] { plan.map { HabitEngine.todayActions($0, hour: hour, band: band) } ?? [] }

    /// Home's one routine: the morning's actions in the morning, the day's during the day, the evening's in the evening.
    func routineNow(band: ReadinessBand?) -> HabitEngine.RoutineNow? { plan.map { HabitEngine.routineNow($0, hour: hour, band: band) } }

    func load(patientId: String, day: String) async {
        request = (patientId, day)
        // Keep what is on screen while refreshing; only a first load shows the skeleton.
        if plan == nil { phase = .loading }
        do {
            let since = HabitEngine.shift(day, by: -(HabitEngine.completionsLookbackDays - 1))
            phase = .loaded(try await backend.habitPlan(patientId: patientId, day: day, since: since))
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "habits.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if plan == nil { phase = .failed(error.userMessage) }
        } catch {
            if plan == nil { phase = .failed(String(describing: error)) }
        }
    }

    func retry() async {
        guard let request else { return }
        await load(patientId: request.patientId, day: request.day)
    }

    /// Check a habit off for today, or undo it. Optimistic; a failed write restores the row.
    func toggle(_ action: HabitAction) async {
        guard case .loaded(let plan) = phase, let request else { return }
        if let completionId = action.completionId {
            remove(completionId: completionId)
            do {
                try await backend.deleteHabitCompletion(id: completionId)
            } catch {
                append(HabitCompletionRow(id: completionId, habitId: action.id, completionDate: plan.day))
                report(error, context: "habits.undo")
            }
        } else {
            let pending = HabitCompletionRow(id: "pending:\(UUID().uuidString)", habitId: action.id, completionDate: plan.day)
            append(pending)
            do {
                let id = try await backend.completeHabit(patientId: request.patientId, habitId: action.id, day: plan.day, at: now())
                replace(pendingId: pending.id, with: id)
                let backend = self.backend, day = plan.day
                Task.detached { try? await backend.evaluateHabitGates(day: day) }
            } catch {
                remove(completionId: pending.id)
                report(error, context: "habits.done")
            }
        }
    }

    // MARK: - The action bank (foundation cards a member may add themselves) and the next call

    enum BankPhase: Equatable {
        case idle, loading
        case loaded([ActionCardRow])
        case failed(String)
    }

    private(set) var bank: BankPhase = .idle
    /// The member's next call with the practice — shown where the plan is still blurred. Nil: none booked, or the
    /// read failed (the "book your call" button is the safe fallback either way).
    private(set) var nextCall: AppointmentRow?

    func loadBank() async {
        if case .loaded = bank { return }
        bank = .loading
        do {
            bank = .loaded(try await backend.actionBank())
        } catch {
            report(error, context: "habits.bank")
            bank = .failed((error as? AppError)?.userMessage ?? String(describing: error))
        }
    }

    func retryBank() async {
        bank = .idle
        await loadBank()
    }

    /// Fail-soft: a missing date only means the button shows instead.
    func loadNextCall() async {
        nextCall = try? await backend.nextAppointment(after: now())
    }

    /// Add a bank card to the member's own plan, then reload the day so it shows everywhere at once.
    /// Returns false (and leaves the plan as it was) when the write fails.
    func add(card: ActionCardRow, slot: HabitSlot?) async -> Bool {
        guard let request else { return false }
        do {
            let row = PlanAccess.ownHabit(from: card, patientId: request.patientId, locale: TodayFocus.locale(), slot: slot)
            _ = try await backend.addOwnHabit(row)
            await load(patientId: request.patientId, day: request.day)
            return true
        } catch {
            report(error, context: "habits.add")
            return false
        }
    }

    /// Remove one of the member's own habits (a prescribed one is the clinician's and never offered here).
    func remove(ownHabitId id: String) async -> Bool {
        guard let request else { return false }
        do {
            try await backend.removeOwnHabit(id: id)
            await load(patientId: request.patientId, day: request.day)
            return true
        } catch {
            report(error, context: "habits.remove")
            return false
        }
    }

    // MARK: - Evolution ladders

    /// The published cards the ladders are walked from. Loaded once per session; a failed read leaves the ladders
    /// out (the action card still shows everything else).
    private(set) var ladderCards: [ActionCardRow]?

    func loadLadders() async {
        guard ladderCards == nil else { return }
        do { ladderCards = try await backend.ladderCards() } catch { report(error, context: "habits.ladders") }
    }

    /// The ladder a habit's card sits on, when it sits on one.
    func ladder(for habit: HabitRow) -> ActionLadder? {
        guard let cardId = habit.habitBankId, let cards = ladderCards else { return nil }
        return LadderLogic.ladder(for: cardId, in: cards)
    }

    /// Why the server refused a level-up, in the member's words; nil = it went through.
    enum LevelUpRefusal: Equatable { case notReady, oneChangePerWeek, locked, unavailable, failed }

    /// Move a habit to its next level (`member_level_up`; the server checks the rules), then reload the day so
    /// Home and the card show the new level at once.
    func levelUp(_ habit: HabitRow) async -> LevelUpRefusal? {
        guard let request else { return .failed }
        do {
            try await backend.levelUp(habitId: habit.id)
            await load(patientId: request.patientId, day: request.day)
            return nil
        } catch let AppError.validation(message) {
            switch message {
            case "not_ready": return .notReady
            case "one_change_per_week": return .oneChangePerWeek
            case "level_locked": return .locked
            default: return .unavailable
            }
        } catch {
            report(error, context: "habits.levelUp")
            return .failed
        }
    }

    // MARK: - The completions on screen (always the CURRENT phase, never a stale copy captured before an await)

    private func mutate(_ change: (inout [HabitCompletionRow]) -> Void) {
        guard case .loaded(var current) = phase else { return }
        change(&current.completions)
        phase = .loaded(current)
    }

    private func append(_ row: HabitCompletionRow) { mutate { $0.append(row) } }
    private func remove(completionId: String) { mutate { $0.removeAll { $0.id == completionId } } }
    private func replace(pendingId: String, with id: String) {
        mutate { rows in
            if let i = rows.firstIndex(where: { $0.id == pendingId }) {
                rows[i] = HabitCompletionRow(id: id, habitId: rows[i].habitId, completionDate: rows[i].completionDate)
            }
        }
    }

    private func report(_ error: Error, context: StaticString) {
        guard let appError = error as? AppError else { return }
        Log.error(appError, in: Log.data, context: context)
        if case .unauthorized = appError { Task { await auth.handleUnauthorized() } }
    }
}
