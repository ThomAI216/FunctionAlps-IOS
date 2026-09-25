import Foundation
import Testing
@testable import FunctionAlps

@Suite("SupabaseBackend — the meal schedule (member_meal_schedule_seed · member_meal_schedule)")
struct MealScheduleBackendTests {
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

    @Test func readsThroughTheSeedRpcAndDecodesTheRows() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"id":"r1","patient_id":"p1","slot":"breakfast","weekday":1,"enabled":false,"remind_at":"08:00:00","source":"intake","learning_enabled":true,"updated_via":"engine","created_at":"2026-09-25T19:00:00+00:00","updated_at":"2026-09-25T19:00:00+00:00"},
         {"id":"r2","patient_id":"p1","slot":"dinner","weekday":1,"enabled":true,"remind_at":"20:00:00","source":"default","learning_enabled":true,"updated_via":"engine","created_at":"2026-09-25T19:00:00+00:00","updated_at":"2026-09-25T19:00:00+00:00"}]
        """)
        let rows = try await make(transport).mealSchedule()
        let schedule = MealSchedule(entries: rows.compactMap(\.entry))
        #expect(schedule.entry(.breakfast, weekday: 1).enabled == false)
        #expect(schedule.entry(.breakfast, weekday: 1).source == .intake)
        #expect(schedule.entry(.dinner, weekday: 1).remindAt == "20:00")
        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/rest/v1/rpc/member_meal_schedule_seed"))
    }

    @Test func savesOnlyTheGivenRowsAsAnUpsertOnTheNaturalKey() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: "")
        let row = MealScheduleRow.write(MealScheduleEntry(slot: .dinner, weekday: 5, enabled: true, remindAt: "21:00", source: .member), patientId: "p1")
        try await make(transport).saveMealSchedule([row])
        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/rest/v1/member_meal_schedule"))
        #expect(request.url.query?.contains("on_conflict=patient_id,slot,weekday") == true)
        #expect(request.headers["Prefer"]?.contains("resolution=merge-duplicates") == true)
        let body = try #require(request.body)
        let sent = try #require(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(sent.count == 1)
        #expect(sent[0]["patient_id"] as? String == "p1")
        #expect(sent[0]["remind_at"] as? String == "21:00:00")
        #expect(sent[0]["source"] as? String == "member")
        #expect(sent[0]["updated_via"] as? String == "ios")
        #expect(sent[0]["weekday"] as? Int == 5)
    }

    @Test func nothingToSaveSendsNothing() async throws {
        let transport = MockTransport()
        try await make(transport).saveMealSchedule([])
        #expect(transport.requests.isEmpty)
    }
}
