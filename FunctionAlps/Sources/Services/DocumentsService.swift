import Foundation
import Observation

/// The member's released documents as one shared, observable value, plus the "a draft plan is being prepared"
/// flag the plan screen needs. Keyed BY PATIENT like `LabResultsService`: `AppDependencies` outlives a sign-out,
/// so a load first asks who is signed in and drops anything held for someone else.
@MainActor
@Observable
final class DocumentsService {
    private(set) var state: Loadable<[MemberDocument]> = .loading
    private(set) var isRefreshing = false
    /// A plan exists but is still a draft. Fails closed: any error reads as "no".
    private(set) var hasDraftPlan = false

    private let backend: any FunctionAlpsBackend
    private let members: MemberService
    private let auth: AuthService
    private let now: @Sendable () -> Date
    private var patientId: String?
    private var inflight: Task<Void, Never>?

    init(backend: any FunctionAlpsBackend, members: MemberService, auth: AuthService, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.members = members
        self.auth = auth
        self.now = now
    }

    var documents: [MemberDocument] { state.value ?? [] }

    func load(force: Bool = false) async {
        if let running = inflight { await running.value; if !force { return } }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetch(force: force)
        }
        inflight = task
        await task.value
        inflight = nil
    }

    private func adopt(_ member: Member) {
        if member.patientId != patientId {
            patientId = member.patientId
            state = .loading
            hasDraftPlan = false
        }
    }

    private func fetch(force: Bool) async {
        do {
            let member = try await members.currentMember(forceRefresh: true)   // medical records: the patient is always re-confirmed with the server, never taken from the member cache
            adopt(member)
            var firstLoad = false
            if case .loading = state { firstLoad = true }
            guard force || firstLoad else { return }
            isRefreshing = !firstLoad
            defer { isRefreshing = false }
            let docs = DocumentsLogic.sorted(try await backend.memberDocuments())
            state = docs.isEmpty ? .empty : .loaded(docs)
        } catch MemberService.MemberError.notRegistered {
            patientId = nil
            state = .empty
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "documents.load")
            if case .unauthorized = error {
                forget()
                await auth.handleUnauthorized()
                return
            }
            if case .loaded = state { return }
            state = .failed(error)
        } catch {
            if case .loaded = state { return }
            state = .failed(.unknown(detail: String(describing: error)))
        }
    }

    /// The plan screen's read. Never throws: a failure means "not known", which shows nothing extra.
    func loadDraftPlan() async {
        guard let member = try? await members.currentMember(forceRefresh: true) else { return }
        adopt(member)
        hasDraftPlan = (try? await backend.hasDraftPlan()) ?? false
    }

    /// What a tap on `doc` does: reads the release's file row, signs the object when there is one, and says
    /// where to go. The member's first open is recorded afterwards by `markSeen`.
    func resolve(_ doc: MemberDocument) async throws -> DocumentDestination {
        var file: DocumentFile?
        if doc.hasFile || doc.linkPath == nil { file = try await backend.memberDocumentFile(releaseId: doc.id) }
        switch DocumentsLogic.plan(for: doc, file: file) {
        case .sign(let bucket, let path):
            return .browser(try await backend.signedDocumentURL(bucket: bucket, path: path))
        case .destination(let destination):
            return destination
        case .unavailable:
            throw AppError.notFound
        }
    }

    /// Records the open, then reflects it locally so "New" goes at once. A failed stamp is only logged.
    func markSeen(_ doc: MemberDocument) async {
        guard doc.isNew else { return }
        do {
            try await backend.markDocumentSeen(releaseId: doc.id)
        } catch {
            if let error = error as? AppError { Log.error(error, in: Log.data, context: "documents.markSeen") }
            return
        }
        guard case .loaded(let docs) = state else { return }
        let stamp = now()
        state = .loaded(docs.map { $0.id == doc.id ? $0.seen(at: stamp) : $0 })
    }

    func forget() {
        patientId = nil
        state = .loading
        hasDraftPlan = false
    }
}

extension MemberDocument {
    func seen(at date: Date) -> MemberDocument {
        MemberDocument(id: id, kind: kind, title: title, sentAt: sentAt, firstSeenAt: firstSeenAt ?? date,
                       hasFile: hasFile, linkPath: linkPath, hasPreview: hasPreview, fromName: fromName)
    }
}
