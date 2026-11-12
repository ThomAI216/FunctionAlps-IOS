import Foundation
import Testing
@testable import FunctionAlps

@Suite("DocumentsService and DocumentsViewModel")
@MainActor
struct DocumentsServiceTests {
    private func make(_ backend: StubBackend) -> DocumentsService {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: MockTransport()), store: store)
        let members = MemberService(sessions: sessions, backend: backend)
        let auth = AuthService(sessions: sessions, state: AppState())
        return DocumentsService(backend: backend, members: members, auth: auth, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    private func report(_ id: String = "r1", seen: Bool = false) -> MemberDocument {
        MemberDocument(id: id, kind: .report, title: "Report", sentAt: Date(timeIntervalSince1970: 1_700_000_000),
                       firstSeenAt: seen ? Date(timeIntervalSince1970: 1_700_100_000) : nil, hasFile: true)
    }

    @Test func loadsLoadedEmptyAndFailedStates() async {
        let backend = StubBackend(); backend.patientId = "p"
        backend.documents = [report("a"), report("b")]
        let service = make(backend)
        #expect({ if case .loading = service.state { true } else { false } }())
        await service.load()
        #expect(service.documents.count == 2)

        let none = StubBackend(); none.patientId = "p"
        let empty = make(none); await empty.load()
        if case .empty = empty.state {} else { Issue.record("expected .empty, got \(empty.state)") }

        let broken = StubBackend(); broken.patientId = "p"; broken.documentsFail = true
        let failed = make(broken); await failed.load()
        if case .failed = failed.state {} else { Issue.record("expected .failed, got \(failed.state)") }
    }

    @Test func anotherPatientNeverSeesTheCache() async {
        let backend = StubBackend(); backend.patientId = "a"; backend.documents = [report()]
        let service = make(backend)
        await service.load()
        backend.patientId = "b"; backend.documents = []
        await service.load()
        if case .empty = service.state {} else { Issue.record("expected .empty for the second member") }
    }

    @Test func draftPlanFailsClosed() async {
        let backend = StubBackend(); backend.patientId = "p"; backend.draftPlan = true
        let service = make(backend)
        await service.loadDraftPlan()
        #expect(service.hasDraftPlan)
        backend.patientId = "other"; backend.draftPlan = false
        await service.loadDraftPlan()
        #expect(!service.hasDraftPlan)
    }

    @Test func tappingAFileSignsItThenMarksItSeen() async {
        let backend = StubBackend(); backend.patientId = "p"
        backend.documents = [report()]
        backend.documentFile = DocumentFile(storageBucket: "document-releases", storagePath: "p/r1.pdf")
        let service = make(backend)
        await service.load()
        let model = DocumentsViewModel(service: service)
        await model.open(model.visible[0])
        #expect(model.page?.url.absoluteString == "https://signed.invalid/p/r1.pdf")
        #expect(backend.signed == ["document-releases/p/r1.pdf"])
        #expect(backend.seen == ["r1"])
        #expect(model.visible[0].isNew == false, "New goes at once")
        #expect(model.openError == nil && model.openingId == nil)
    }

    @Test func aSeenDocumentIsNotStampedAgain() async {
        let backend = StubBackend(); backend.patientId = "p"
        backend.documents = [report(seen: true)]
        backend.documentFile = DocumentFile(storageBucket: "invoices", storagePath: "p/i.pdf")
        let service = make(backend)
        await service.load()
        let model = DocumentsViewModel(service: service)
        await model.open(model.visible[0])
        #expect(backend.seen.isEmpty)
    }

    @Test func aLinkOpensTheMembersSiteAndAPlanOpensThePlan() async {
        let backend = StubBackend(); backend.patientId = "p"
        backend.documents = [
            MemberDocument(id: "l", kind: .resource, title: "Res", sentAt: Date(timeIntervalSince1970: 1_700_000_000), hasFile: false, linkPath: "/dashboard/library/x"),
            MemberDocument(id: "c", kind: .carePlan, title: "Plan", sentAt: Date(timeIntervalSince1970: 1_600_000_000), hasFile: false, linkPath: "/dashboard/plan"),
        ]
        let service = make(backend)
        await service.load()
        let model = DocumentsViewModel(service: service)
        await model.open(model.visible[0])
        #expect(model.page?.url.absoluteString == "https://members.functionalps.ch/dashboard/library/x")
        await model.open(model.visible[1])
        #expect(model.showPlan)
    }

    @Test func aDocumentWithNothingToOpenSetsAnErrorAndIsNotMarkedSeen() async {
        let backend = StubBackend(); backend.patientId = "p"
        backend.documents = [report()]
        backend.documentFile = nil
        let service = make(backend)
        await service.load()
        let model = DocumentsViewModel(service: service)
        await model.open(model.visible[0])
        #expect(model.openError != nil && model.page == nil)
        #expect(backend.seen.isEmpty)
    }

    @Test func filterChangesTheVisibleList() async {
        let backend = StubBackend(); backend.patientId = "p"
        backend.documents = [report("a"), MemberDocument(id: "i", kind: .invoice, title: "Inv", sentAt: Date(timeIntervalSince1970: 1_600_000_000))]
        let service = make(backend)
        await service.load()
        let model = DocumentsViewModel(service: service)
        #expect(model.visible.count == 2)
        model.filter = .invoices
        #expect(model.visible.map(\.id) == ["i"])
        #expect(model.count(for: .reports) == 1 && model.unseen == 2)
        model.filter = .labReports
        #expect(model.visible.isEmpty)
    }
}
