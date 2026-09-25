import Foundation
import Testing
@testable import FunctionAlps

/// The wire: `POST /rest/v1/rpc/get_member_lab_results?select=<the 19 columns>` under the member's bearer.
@Suite("SupabaseBackend — lab results (get_member_lab_results)")
struct LabResultsBackendTests {
    private func make(_ transport: MockTransport) -> SupabaseBackend {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store)
        let requester = AuthorizedRequester(sessions: sessions, transport: transport)
        return SupabaseBackend(
            rest: PostgRESTClient(environment: Fixtures.environment, requester: requester),
            functions: EdgeFunctionClient(environment: Fixtures.environment, requester: requester),
            storage: StorageClient(environment: Fixtures.environment, requester: requester)
        )
    }

    @Test func callsTheFunctionWithThePinnedColumns() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: LabResultsLogicTests.fixture)
        let rows = try await make(transport).labResults()
        #expect(rows.count == 5)
        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/rest/v1/rpc/get_member_lab_results"))
        let query = try #require(request.url.query)
        #expect(query.contains("select=" + LabResultRow.columns.joined(separator: ",")))
        #expect(request.headers["Authorization"] == "Bearer access-1")
        #expect(request.headers["apikey"] == "sb_publishable_test")
    }

    /// No approved release = an empty array, not an error (PostgREST answers a set-returning function with `[]`).
    @Test func noReleaseIsEmpty() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: "[]")
        let rows = try await make(transport).labResults()
        #expect(rows.isEmpty)
    }

    /// A column the function no longer returns fails the DECODE, loudly — never a silently blank screen.
    @Test func missingColumnIsADecodingError() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"[{"release_id":"r","lab_run_id":"l","sampled_at":null,"language":"fr","biomarker_result_id":"m","status":"in_range"}]"#)
        await #expect(throws: AppError.self) {
            _ = try await make(transport).labResults()
        }
    }
}
