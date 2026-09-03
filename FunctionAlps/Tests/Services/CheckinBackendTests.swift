import Foundation
import Testing
@testable import FunctionAlps

@Suite("SupabaseBackend — check-in moments")
struct CheckinBackendTests {
    private let t0 = Date(timeIntervalSince1970: 1_788_350_400) // 2026-09-02T12:00:00Z

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

    private func json(_ request: HTTPRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func decodesMomentsAndDropsUnknownSlots() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"slot":"morning","submitted_at":"2026-09-02T06:10:00+00:00","energy_body":60,"energy_mind":80,"energy_stability":null,"energy_overall":70,"mood_score":null,"stress_score":58,"sleep_overall":79,"sleep_refreshed":40,"sleep_duration_min":480,"sleep_latency_band":"lt_15","sleep_wake_count":"0","pills":{"day_intent":["intent_calm"]},"note":null},
         {"slot":"brunch","submitted_at":"2026-09-02T09:00:00+00:00","pills":{}}]
        """)
        let moments = try await make(transport).checkinMoments(patientId: "p1", day: "2026-09-02")
        #expect(moments.count == 1)
        #expect(moments[0].slot == .morning)
        #expect(moments[0].stressScore == 58)
        #expect(moments[0].pills == ["day_intent": ["intent_calm"]])
        let query = try #require(transport.requests.first?.url.query)
        #expect(query.contains("checkin_date=eq.2026-09-02"))
        #expect(query.contains("order=submitted_at.asc"))
    }

    @Test func momentUpsertWritesEveryColumnWithExplicitNulls() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: "")
        let m = CheckinMoment(slot: .midday, submittedAt: t0, energyBody: 60, energyOverall: 70, stressScore: 58, pills: ["drained": ["travel"]])
        try await make(transport).upsertCheckinMoment(patientId: "p1", day: "2026-09-02", moment: m)
        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/rest/v1/patient_checkin_moments"))
        #expect(request.url.query?.contains("on_conflict=patient_id,checkin_date,slot") == true)
        #expect(request.headers["Prefer"]?.contains("resolution=merge-duplicates") == true)
        let body = try json(request)
        #expect(body["patient_id"] as? String == "p1")
        #expect(body["checkin_date"] as? String == "2026-09-02")
        #expect(body["slot"] as? String == "midday")
        #expect(body["submitted_at"] as? String == "2026-09-02T12:00:00.000Z")
        #expect(body["energy_body"] as? Int == 60)
        #expect(body["stress_score"] as? Int == 58)
        #expect(body["energy_mind"] is NSNull)
        #expect(body["note"] is NSNull)
        #expect((body["pills"] as? [String: [String]]) == ["drained": ["travel"]])
        #expect(body.count == 17)
    }

    @Test func summaryUpsertOmitsSleepUnlessTheDayHasIt() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: "")
        transport.enqueue(status: 201, json: "")
        let backend = make(transport)
        try await backend.upsertDailySummary(patientId: "p1", day: "2026-09-02", patch: DaySummaryPatch(energyOverall: 70, legacyEnergy: 4, recovery: 7, completedAt: t0))
        try await backend.upsertDailySummary(patientId: "p1", day: "2026-09-02", patch: DaySummaryPatch(sleep: .init(sleepOverall: 79, sleepLatencyBand: "lt_15", legacySleep: 4), completedAt: t0))

        let first = try json(transport.requests[0])
        #expect(transport.requests[0].url.query?.contains("on_conflict=patient_id,checkin_date") == true)
        #expect(first["energy_overall"] as? Int == 70)
        #expect(first["energy"] as? Int == 4)
        #expect(first["recovery"] as? Int == 7)
        #expect(first["soreness"] is NSNull)
        #expect(first["sleep_overall"] == nil)
        #expect(first["sleep"] == nil)
        #expect(first["last_submission_form"] as? String == "functional")
        #expect(first["functional_completed_at"] as? String == "2026-09-02T12:00:00.000Z")
        #expect(first["completed_at"] as? String == "2026-09-02T12:00:00.000Z")
        #expect(first["digestion"] == nil)
        #expect(first["functional_detail"] == nil)

        let second = try json(transport.requests[1])
        #expect(second["sleep_overall"] as? Int == 79)
        #expect(second["sleep_latency_band"] as? String == "lt_15")
        #expect(second["sleep_wake_count"] is NSNull)
        #expect(second["sleep"] as? Int == 4)
    }

    @Test func eventsAreInsertedAsOneBatch() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: "")
        let backend = make(transport)
        try await backend.insertCheckinEvents(patientId: "p1", events: [CheckinEvent(dimension: "energy", value: 70, ts: t0), CheckinEvent(dimension: "stress", value: 58, ts: t0)])
        try await backend.insertCheckinEvents(patientId: "p1", events: [])
        #expect(transport.requestCount == 1)
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix("/rest/v1/nb_checkin_events"))
        #expect(request.headers["Prefer"] == "return=minimal")
        let body = try #require(request.body)
        let rows = try #require(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(rows.count == 2)
        #expect(rows[0]["patient_id"] as? String == "p1")
        #expect(rows[0]["dimension"] as? String == "energy")
        #expect(rows[0]["source"] as? String == "daily")
        #expect(rows[1]["value"] as? Int == 58)
    }

    @Test func carryReadsTheNoWipeColumns() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"[{"recovery":7,"soreness":null,"recent_load":null,"recent_mental_load":2,"energy_body":33,"energy_mind":null,"energy_stability":null,"energy_overall":null,"mood_score":null,"stress_score":null,"sleep_overall":88,"sleep_refreshed":null,"sleep_duration_min":null,"sleep_latency_band":null,"sleep_wake_count":null,"energy":2,"mood":null,"sleep":5,"stress":null}]"#)
        let carry = try #require(try await make(transport).dailyCheckinCarry(patientId: "p1", day: "2026-09-02"))
        #expect(carry.recovery == 7)
        #expect(carry.recentMentalLoad == 2)
        #expect(carry.energyBody == 33)
        #expect(carry.sleepOverall == 88)
        #expect(carry.sleep == 5)
        let query = try #require(transport.requests.first?.url.query)
        #expect(query.contains("recent_mental_load"))
        #expect(query.contains("checkin_date=eq.2026-09-02"))
    }
}
