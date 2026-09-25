import Foundation
import Testing
@testable import FunctionAlps

/// The shared cache is keyed by PATIENT: another member signing in on the same phone never sees, and
/// never keeps, the previous member's results.
@Suite("LabResultsService")
@MainActor
struct LabResultsServiceTests {
    private func make(backend: StubBackend) -> LabResultsService {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: MockTransport()), store: store)
        let members = MemberService(sessions: sessions, backend: backend)
        let auth = AuthService(sessions: sessions, state: AppState())
        return LabResultsService(backend: backend, members: members, auth: auth)
    }

    private func rows() throws -> [LabResultRow] {
        try JSON.decode([LabResultRow].self, from: Data(LabResultsLogicTests.fixture.utf8))
    }

    @Test func loadsOncePerPatientAndRefreshesOnDemand() async throws {
        let backend = StubBackend()
        backend.patientId = "patient-a"
        backend.labRows = try rows()
        let service = make(backend: backend)

        await service.load()
        #expect(service.results.map(\.releaseId) == ["rel-sep", "rel-mar"])
        #expect(backend.labResultsCalls == 1)

        await service.load()
        #expect(backend.labResultsCalls == 1, "a second screen reads the same load")

        await service.load(force: true)
        #expect(backend.labResultsCalls == 2, "pull to refresh re-reads")
        #expect(service.result("rel-sep")?.markers.count == 3)
    }

    @Test func anotherPatientNeverSeesTheCache() async throws {
        let backend = StubBackend()
        backend.patientId = "patient-a"
        backend.labRows = try rows()
        let service = make(backend: backend)
        await service.load()
        #expect(!service.results.isEmpty)

        // Sign-out, sign-in as someone else on the same phone: the server now names another patient.
        backend.patientId = "patient-b"
        backend.labRows = []
        await service.load()
        #expect(service.results.isEmpty)
        if case .empty = service.state {} else { Issue.record("expected .empty for the second member, got \(service.state)") }
        #expect(backend.labResultsCalls == 2)
        #expect(service.result("rel-sep") == nil, "the first member's release must be gone")
    }

    @Test func nothingApprovedIsEmptyNotAnError() async throws {
        let backend = StubBackend()
        backend.patientId = "patient-a"
        backend.labRows = []
        let service = make(backend: backend)
        await service.load()
        if case .empty = service.state {} else { Issue.record("expected .empty, got \(service.state)") }
    }

    @Test func unregisteredAccountIsEmpty() async throws {
        let backend = StubBackend()
        backend.patientId = nil   // no patient row…
        backend.registerFails = true   // …and no registration either → MemberError.notRegistered
        let service = make(backend: backend)
        await service.load()
        if case .empty = service.state {} else { Issue.record("expected .empty, got \(service.state)") }
        #expect(backend.labResultsCalls == 0, "no patient, no read")
    }

    @Test func forgetDropsEverything() async throws {
        let backend = StubBackend()
        backend.patientId = "patient-a"
        backend.labRows = try rows()
        let service = make(backend: backend)
        await service.load()
        service.forget()
        #expect(service.results.isEmpty)
        if case .loading = service.state {} else { Issue.record("expected .loading after forget") }
        await service.load()
        #expect(backend.labResultsCalls == 2, "the next load starts from nothing")
    }
}
