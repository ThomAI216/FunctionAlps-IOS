import Foundation
import Testing
@testable import FunctionAlps

@Suite("SupabaseBackend (PostgREST wire format)")
struct SupabaseBackendTests {
    private func make(_ transport: MockTransport) -> SupabaseBackend {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store)
        let requester = AuthorizedRequester(sessions: sessions, transport: transport)
        return SupabaseBackend(
            rest: PostgRESTClient(environment: Fixtures.environment, requester: requester),
            functions: EdgeFunctionClient(environment: Fixtures.environment, requester: requester)
        )
    }

    @Test func decodesProfileRow() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"app_sex":"female","app_age":41,"app_height_cm":168.5,"app_weight_kg":62,"activity_level":"moderate","health_goals":["energy","sleep"],"current_complaints":[],"dietary_pattern":"mediterranean","target_calories":1900,"target_protein_g":110,"target_carbs_g":190,"target_fat_g":70,"goal_mode":"maintain","onboarding_completed_at":"2026-08-20T09:12:33.123456+00:00","locale":"fr"}]
        """)
        let loaded = try await make(transport).memberProfile(patientId: "p1")
        let profile = try #require(loaded)
        #expect(profile.sex == .female)
        #expect(profile.age == 41)
        #expect(profile.heightCm == 168.5)
        #expect(profile.healthGoals == ["energy", "sleep"])
        #expect(profile.goalMode == .maintain)
        #expect(profile.onboardingCompletedAt != nil)
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix("/rest/v1/nb_patient_app_profiles"))
        #expect(request.url.query?.contains("patient_id=eq.p1") == true)
        #expect(request.headers["Authorization"] == "Bearer access-1")
        #expect(request.headers["apikey"] == "sb_publishable_test")
    }

    @Test func profileMissingIsNil() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: "[]")
        let profile = try await make(transport).memberProfile(patientId: "p1")
        #expect(profile == nil)
    }

    @Test func decodesMealsAndQueriesSince() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"id":"m1","logged_at":"2026-09-02T07:15:00+00:00","meal_type":"breakfast","name":"Oats","source":"photo","analysis_status":"complete","total_calories":420.5,"total_protein_g":18,"total_carbs_g":60,"total_fat_g":12,"photo_url":"uid/m1.jpg"},
         {"id":"m2","logged_at":"2026-09-02T12:05:00+00:00","meal_type":"lunch","name":null,"source":"text","analysis_status":"analyzing","total_calories":null,"total_protein_g":null,"total_carbs_g":null,"total_fat_g":null,"photo_url":null}]
        """)
        let since = Date(timeIntervalSince1970: 1_788_307_200) // 2026-09-02T00:00:00Z
        let meals = try await make(transport).meals(patientId: "p1", since: since)
        #expect(meals.count == 2)
        #expect(meals[0].mealType == .breakfast)
        #expect(meals[0].totalCalories == 420.5)
        #expect(meals[0].isAnalysed)
        #expect(meals[1].analysisStatus == .analyzing)
        #expect(!meals[1].isAnalysed)
        let query = try #require(transport.requests.first?.url.query)
        #expect(query.contains("logged_at=gte.2026-09-02T00:00:00.000Z"))
        #expect(query.contains("order=logged_at.desc"))
    }

    @Test func checkinPrefersV2MarkersAndKeepsCalmness() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: """
        [{"checkin_date":"2026-09-02","functional_completed_at":"2026-09-02T08:00:00Z","intelligence_completed_at":null,"energy_overall":72,"mood_score":80,"sleep_overall":65,"stress_score":58,"gut_overall":null,"energy":7,"mood":8,"sleep":6,"stress":4}]
        """)
        let loaded = try await make(transport).dailyCheckin(patientId: "p1", day: "2026-09-02")
        let checkin = try #require(loaded)
        #expect(checkin.isFunctionalDone)
        #expect(!checkin.isGutDone)
        #expect(checkin.energy == 72)
        #expect(checkin.calmness == 58)
    }

    @Test func checkinFallsBackToLegacyColumnsOn400() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 400, json: #"{"code":"42703","message":"column patient_daily_checkins.energy_overall does not exist"}"#)
        transport.enqueue(status: 200, json: """
        [{"checkin_date":"2026-09-02","functional_completed_at":"2026-09-02T08:00:00Z","intelligence_completed_at":null,"energy":10,"mood":1,"sleep":5,"stress":10}]
        """)
        let loaded = try await make(transport).dailyCheckin(patientId: "p1", day: "2026-09-02")
        let checkin = try #require(loaded)
        #expect(transport.requestCount == 2)
        #expect(transport.requests[1].url.query?.contains("energy_overall") == false)
        #expect(checkin.energy == 100)
        #expect(checkin.mood == 0)
        #expect(checkin.calmness == 0)   // legacy stress 10/10 → calmness 0
    }

    @Test func countParsesContentRange() async throws {
        let transport = MockTransport()
        transport.enqueue { _ in HTTPResponse(status: 206, headers: ["Content-Range": "0-0/3"], body: Data("[{\"id\":\"x\"}]".utf8)) }
        let count = try await make(transport).unreadClinicianMessageCount(patientId: "p1")
        #expect(count == 3)
        let request = try #require(transport.requests.first)
        #expect(request.headers["Prefer"] == "count=exact")
        #expect(request.url.query?.contains("read_by_patient_at=is.null") == true)
        #expect(request.url.query?.contains("sender_type=eq.clinician") == true)
    }

    @Test func rpcScalarNullMeansNoPatient() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: "null")
        let backend = make(transport)
        let none = try await backend.currentPatientId()
        #expect(none == nil)
        transport.enqueue(status: 200, json: "\"22222222-2222-2222-2222-222222222222\"")
        let some = try await backend.currentPatientId()
        #expect(some == "22222222-2222-2222-2222-222222222222")
        #expect(transport.requests.first?.url.path.hasSuffix("/rest/v1/rpc/current_member_patient_id") == true)
    }
}
