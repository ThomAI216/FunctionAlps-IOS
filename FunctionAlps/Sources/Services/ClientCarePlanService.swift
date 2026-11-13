import Foundation
import Observation

/// The client's care plan (what the practice shared) as one shared, observable value: Today's card, the Plan page
/// and its sub-screens read the same load. Loaded by the first screen that needs it; pull-to-refresh re-reads.
///
/// States (rule 5): `.loading` before the first answer · `.loaded` · `.empty` (the practice has shared nothing yet — the
/// screens fall back to the existing plan page) · `.failed`. A failed refresh keeps what is on screen. The data is
/// medical: `forget()` drops it when the session ends, and a load first asks who is signed in so one member's plan is
/// never shown to another.
@MainActor
@Observable
final class ClientCarePlanService {
    private(set) var state: Loadable<ClientCarePlanRaw> = .loading
    /// The last 14 day rows the app already holds — the mini curves on "Your situation & evolution". Soft: absent = no curves.
    private(set) var history: [DailyCheckin] = []

    private let backend: any FunctionAlpsBackend
    private let members: MemberService
    private let auth: AuthService
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var patientId: String?
    private var inflight: Task<Void, Never>?

    init(backend: any FunctionAlpsBackend, members: MemberService, auth: AuthService,
         now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.backend = backend
        self.members = members
        self.auth = auth
        self.now = now
        self.calendar = calendar
    }

    var plan: ClientCarePlanRaw? { state.value }

    /// Reads once; `force` re-reads. Concurrent callers share one load.
    func load(force: Bool = false) async {
        if let running = inflight { await running.value; if !force { return } }
        if !force, case .loaded = state { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetch()
        }
        inflight = task
        await task.value
        inflight = nil
    }

    private func fetch() async {
        do {
            let member = try await members.currentMember(forceRefresh: true)   // medical records: the patient is always re-confirmed with the server, never taken from the member cache
            if member.patientId != patientId {
                patientId = member.patientId
                state = .loading
                history = []
            }
            let raw = try await backend.clientCarePlan()
            state = raw.isEmpty ? .empty : .loaded(raw)
            let current = now()
            let since = ISO8601.dayString(calendar.date(byAdding: .day, value: -13, to: current) ?? current, calendar: calendar)
            history = (try? await backend.dailyCheckins(patientId: member.patientId, since: since)) ?? []
        } catch MemberService.MemberError.notRegistered {
            patientId = nil
            state = .empty
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "clientCarePlan.load")
            if case .unauthorized = error {
                forget()
                await auth.handleUnauthorized()
                return
            }
            // Keep what is on screen while a refresh fails; only a first load shows the error.
            if case .loaded = state { return }
            state = .failed(error)
        } catch {
            if case .loaded = state { return }
            state = .failed(.unknown(detail: String(describing: error)))
        }
    }

    /// Drops everything held. The next load starts from nothing.
    func forget() {
        patientId = nil
        history = []
        state = .loading
    }
}
