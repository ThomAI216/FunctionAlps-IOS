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

    /// Today's habits in the order the card shows them (see `HabitEngine.todayActions`).
    var actions: [HabitAction] { plan.map { HabitEngine.todayActions($0, hour: hour) } ?? [] }

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

    private func report(_ error: Error, context: String) {
        guard let appError = error as? AppError else { return }
        Log.error(appError, in: Log.data, context: context)
        if case .unauthorized = appError { Task { await auth.handleUnauthorized() } }
    }
}
