import Foundation
import Testing
@testable import FunctionAlps

/// The Foundational week's wire format and its one hard rule: nothing is ever written for the example.
@Suite("SupabaseBackend — Foundational week")
struct FoundationalWeekBackendTests {
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

    private func body(_ request: HTTPRequest) throws -> [String: Any] {
        let data = try #require(request.body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func readsTheExampleWeekThroughItsRpcWithTheDefaultSlug() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"{"example":true,"from":"2001-01-01","to":"2001-01-07","plans":[],"days":[{"date":"2001-01-01","plan_id":"ex1","meals":[]}]}"#)
        let range = try await make(transport).exampleWeek()
        #expect(range.example)
        #expect(range.days.count == 1)
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix("/rest/v1/rpc/member_example_week"))
        #expect(try body(request).isEmpty)   // the server's default slug is 'foundational-week'
    }

    @Test func readsTheExampleGroceriesThroughTheirOwnRpc() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"{"example":true,"plan_id":"ex1","period_start":"2001-01-01","period_end":"2001-01-07","aisles":[],"custom":[]}"#)
        let list = try await make(transport).exampleGroceries()
        #expect(list.example)
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix("/rest/v1/rpc/member_example_groceries"))
    }

    @Test func aDeliveredPlanIsAtLeastOneRecipeIdFromThePlanRecipeIdsRpc() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"["6b1d2c3e-0000-4000-8000-000000000001"]"#)
        transport.enqueue(status: 200, json: "[]")
        transport.enqueue(status: 200, json: #"[{"member_plan_recipe_ids":"6b1d2c3e-0000-4000-8000-000000000001"}]"#)
        let backend = make(transport)
        #expect(try await backend.hasDeliveredPlan() == true)
        #expect(try await backend.hasDeliveredPlan() == false)
        #expect(try await backend.hasDeliveredPlan() == true)   // either PostgREST shape of a set-returning function
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix("/rest/v1/rpc/member_plan_recipe_ids"))
    }

    @Test func tickingTheExampleWritesNothing() async throws {
        let transport = MockTransport()
        let service = MealPlanService(backend: make(transport))
        let example = GroceryList(planId: "ex1", periodStart: "2001-01-01", periodEnd: "2001-01-07", aisles: [], custom: [], example: true)
        try await service.setChecked(patientId: "pat", list: example, target: .food("f1"), checked: true)
        try await service.setChecked(patientId: "pat", list: example, target: .custom("c1"), checked: true)
        #expect(transport.requests.isEmpty)
    }

    @Test func theBackendItselfRefusesToWriteTheExample() async throws {
        let transport = MockTransport()
        let example = GroceryList(planId: "ex1", periodStart: "2001-01-01", periodEnd: "2001-01-07", aisles: [], custom: [], example: true)
        await #expect(throws: AppError.self) {
            try await make(transport).setGroceryChecked(patientId: "pat", list: example, target: .food("f1"), checked: true)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func aMembersOwnListStillWrites() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: "")
        let own = GroceryList(planId: "p1", periodStart: "2026-11-16", periodEnd: "2026-11-22", aisles: [], custom: [])
        try await MealPlanService(backend: make(transport)).setChecked(patientId: "pat", list: own, target: .food("f1"), checked: true)
        #expect(transport.requests.count == 1)
    }
}
