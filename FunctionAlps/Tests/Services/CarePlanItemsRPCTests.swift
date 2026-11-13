import Foundation
import Testing
@testable import FunctionAlps

/// The app must never read `care_plan_items` itself (a member session can read every column of its own rows,
/// clinician rationale included). Both reads go through `member_care_plan_items()` — CLINICAL migration 350.
@Suite("Care-plan items are read through the safe RPC")
struct CarePlanItemsRPCTests {
    private struct IdRow: Decodable, Sendable { let id: String }

    private func client(_ transport: MockTransport) -> PostgRESTClient {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store)
        return PostgRESTClient(environment: Fixtures.environment, requester: AuthorizedRequester(sessions: sessions, transport: transport))
    }

    @Test func selectRPCIsAGetToTheFunctionPathWithTheQuery() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"[{"id":"i-1"}]"#)
        let rows: [IdRow] = try await client(transport).selectRPC(SupabaseBackend.carePlanItemsFunction, query: SupabaseBackend.planItemsQuery(planId: "cp-1"))
        #expect(rows.map(\.id) == ["i-1"])
        let request = try #require(transport.requests.first)
        #expect(request.method == .get)
        #expect(request.url.path == "/rest/v1/rpc/member_care_plan_items")
        let query = request.url.query ?? ""
        #expect(query.contains("care_plan_id=eq.cp-1"))
        #expect(query.contains("status=in.(pushed_to_app,approved)"))
    }

    @Test func neitherQuerySendsAVisibilityFilter() {
        for query in [SupabaseBackend.planItemsQuery(planId: "cp-1"), SupabaseBackend.focusItemsQuery(planId: "cp-1")] {
            #expect(!query.contains { $0.name == "visibility_class" })
            #expect(!query.contains { ($0.value ?? "").contains("visibility_class") })
        }
    }

    @Test func theFocusQueryKeepsItsFiltersAndColumns() {
        let query = SupabaseBackend.focusItemsQuery(planId: "cp-1")
        #expect(query.contains { $0.name == "select" && $0.value == "id,title,objective,sort_order" })
        #expect(query.contains { $0.name == "is_weekly_focus" && $0.value == "eq.true" })
        #expect(query.contains { $0.name == "care_plan_id" && $0.value == "eq.cp-1" })
    }

    @Test func theSelectedColumnsAreAllReturnedByTheFunction() {
        let returned: Set<String> = ["id", "care_plan_id", "programme_id", "phase_id", "phase", "domain", "item_kind", "title", "objective",
                                     "instruction_text", "patient_safe_explanation", "status", "start_date", "review_date", "planned_end_date",
                                     "duration_weeks", "dose_value", "dose_unit", "frequency_text", "cadence", "cadence_days", "is_weekly_focus",
                                     "focus_week", "sort_order", "habit_bank_id", "created_at", "updated_at"]
        for query in [SupabaseBackend.planItemsQuery(planId: "cp-1"), SupabaseBackend.focusItemsQuery(planId: "cp-1")] {
            let columns = (query.first { $0.name == "select" }?.value ?? "").split(separator: ",").map(String.init)
            #expect(!columns.isEmpty && Set(columns).isSubset(of: returned))
        }
    }
}
