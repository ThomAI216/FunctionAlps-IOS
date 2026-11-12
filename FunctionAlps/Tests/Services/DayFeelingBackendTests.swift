import Foundation
import Testing
@testable import FunctionAlps

@Suite("SupabaseBackend — feeling for the day")
struct DayFeelingBackendTests {
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

    @Test func readsTheDaysFeelingWithItsPillGroupsAsWritten() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"day":"2026-11-12","mood":82,"energy":28,"motivation":null,"pills":{"mood_helped":["got_daylight"],"energy_why":["poor_sleep","woke_tired"]},"end_rule":"energy_low_rest_good"}]
        """)
        let feeling = try #require(try await make(transport).dayFeeling(patientId: "p1", day: "2026-11-12"))
        #expect(feeling.mood == 82 && feeling.energy == 28 && feeling.motivation == nil)
        #expect(feeling.pills == ["mood_helped": ["got_daylight"], "energy_why": ["poor_sleep", "woke_tired"]])
        #expect(feeling.endRule == "energy_low_rest_good")
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix("/rest/v1/patient_day_feelings"))
        #expect(request.url.query?.contains("day=eq.2026-11-12") == true)
    }

    @Test func noRowIsNoFeeling() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: "[]")
        #expect(try await make(transport).dayFeeling(patientId: "p1", day: "2026-11-12") == nil)
    }

    @Test func savingUpsertsOnPatientAndDayWithExplicitNulls() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: "")
        let feeling = DayFeeling(day: "2026-11-12", mood: 82, energy: 28, motivation: nil, pills: ["energy_why": ["poor_sleep"]], endRule: "energy_low_rest_good")
        try await make(transport).saveDayFeeling(patientId: "p1", feeling: feeling)
        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/rest/v1/patient_day_feelings"))
        #expect(request.url.query?.contains("on_conflict=patient_id,day") == true)
        let body = try #require(request.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["patient_id"] as? String == "p1")
        #expect(json["day"] as? String == "2026-11-12")
        #expect(json["mood"] as? Int == 82)
        #expect(json["motivation"] is NSNull)
        #expect((json["pills"] as? [String: [String]]) == ["energy_why": ["poor_sleep"]])
        #expect(json["end_rule"] as? String == "energy_low_rest_good")
        #expect(json.count == 7)
    }
}
