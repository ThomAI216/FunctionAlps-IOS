import Foundation
import Observation

/// The member's released lab results as one shared, observable value: the list, the result and the
/// marker sheet all read the same load, so pushing from one to the next costs no request and a deep
/// link straight onto a release still loads what it needs.
///
/// The cache is KEYED BY PATIENT. `AppDependencies` outlives a sign-out, and lab results are medical
/// data: a load first asks who is signed in (the server's answer, via `MemberService`) and drops
/// anything held for someone else before it reads. Another member's results are never shown, and
/// never even kept, on this phone.
@MainActor
@Observable
final class LabResultsService {
    private(set) var state: Loadable<[LabResult]> = .loading
    private(set) var isRefreshing = false

    private let backend: any FunctionAlpsBackend
    private let members: MemberService
    private let auth: AuthService
    private var patientId: String?
    private var inflight: Task<Void, Never>?

    init(backend: any FunctionAlpsBackend, members: MemberService, auth: AuthService) {
        self.backend = backend
        self.members = members
        self.auth = auth
    }

    var results: [LabResult] {
        if case .loaded(let r) = state { return r }
        return []
    }

    func result(_ releaseId: String) -> LabResult? {
        results.first { $0.releaseId == releaseId }
    }

    /// Reads once per patient; `force` re-reads (pull to refresh). Concurrent callers share one load.
    func load(force: Bool = false) async {
        if let running = inflight { await running.value; if !force { return } }
        let task = Task { [weak self] in await self?.fetch(force: force) }
        inflight = task
        await task.value
        inflight = nil
    }

    private func fetch(force: Bool) async {
        do {
            let member = try await members.currentMember()
            if member.patientId != patientId {
                // Someone else, or nobody yet: whatever is held is not theirs.
                patientId = member.patientId
                state = .loading
            }
            var firstLoad = false
            if case .loading = state { firstLoad = true }
            guard force || firstLoad else { return }
            isRefreshing = !firstLoad
            defer { isRefreshing = false }
            let results = LabResultsLogic.group(try await backend.labResults())
            state = results.isEmpty ? .empty : .loaded(results)
        } catch MemberService.MemberError.notRegistered {
            patientId = nil
            state = .empty
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "labs.load")
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

    /// Drops everything held. Called when the session is gone; the next load starts from nothing.
    func forget() {
        patientId = nil
        state = .loading
    }
}
