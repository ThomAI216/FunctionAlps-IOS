import Foundation
import Testing
@testable import FunctionAlps

@Suite("SupabaseBackend + HabitsService — the Habit Loop (habits · habit_completions · evaluate-gates)")
struct HabitsBackendTests {
    private func make(_ transport: MockTransport) -> (SupabaseBackend, SessionManager) {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store)
        let requester = AuthorizedRequester(sessions: sessions, transport: transport)
        let backend = SupabaseBackend(
            rest: PostgRESTClient(environment: Fixtures.environment, requester: requester),
            functions: EdgeFunctionClient(environment: Fixtures.environment, requester: requester),
            storage: StorageClient(environment: Fixtures.environment, requester: requester)
        )
        return (backend, sessions)
    }

    private func json(_ request: HTTPRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private let planRow = #"[{"id":"cp-1","title":"Care plan — 2026-08-15","start_date":"2026-09-01","objective_line":"Getting towards more stamina"}]"#
    private let habitRows = """
    [{"id":"h-1","care_plan_item_id":"i-1","title":"10-min walk after lunch & dinner","description":"Easy pace","frequency_rule":"FREQ=DAILY",
      "status":"active","source":"prescribed","pillar":null,"slot":null,"appears_after_habit_id":null,"easy_title":null,"easy_description":null,
      "rev_title":null,"rev_description":null,"created_at":"2026-08-16T07:04:20.968438+00:00"},
     {"id":"h-2","care_plan_item_id":null,"title":"A glass of water before coffee","description":null,"frequency_rule":"RRULE:FREQ=DAILY",
      "status":"active","source":"self_initiated","pillar":"nutrition","slot":"morning","appears_after_habit_id":null,"easy_title":null,
      "easy_description":null,"rev_title":null,"rev_description":null,"created_at":"2026-08-17T11:49:23.66254+00:00"}]
    """
    private let completionRows = #"[{"id":"c-1","habit_id":"h-1","completion_date":"2026-09-24"}]"#
    private let phaseRows = #"[{"phase_key":"p1","week_start":1,"week_end":2,"title":"Settle","summary":null}]"#

    @Test func loadsTheDayInFourReadsUnderTheMembersSession() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: planRow)
        transport.enqueue(status: 200, json: habitRows)
        transport.enqueue(status: 200, json: completionRows)
        transport.enqueue(status: 200, json: phaseRows)
        let (backend, _) = make(transport)

        let plan = try await backend.habitPlan(patientId: "p-1", day: "2026-09-25", since: "2026-07-18")
        #expect(plan.header?.objectiveLine == "Getting towards more stamina")
        #expect(plan.habits.map(\.id) == ["h-1", "h-2"])
        #expect(plan.habits[1].isSelfInitiated)
        #expect(plan.habits[1].slotValue == .morning)
        #expect(plan.habits[0].createdDay == "2026-08-16")
        #expect(plan.completions.first?.day == "2026-09-24")
        #expect(plan.phases.first?.title == "Settle")

        let paths = transport.requests.map { $0.url.path }
        #expect(paths == ["/rest/v1/care_plans", "/rest/v1/habits", "/rest/v1/habit_completions", "/rest/v1/care_plan_phases"])
        let q = transport.requests.map { $0.url.query ?? "" }
        #expect(q[0].contains("status=eq.active") && q[0].contains("objective_line") && q[0].contains("limit=1"))
        #expect(q[1].contains("status=neq.cancelled") && q[1].contains("patient_id=eq.p-1") && !q[1].contains("gate_criteria"))
        #expect(q[2].contains("completion_date=gte.2026-07-18") && q[2].contains("completion_date=lte.2026-09-25"))
        #expect(q[3].contains("care_plan_id=eq.cp-1") && !q[3].contains("gate_criteria"))
    }

    @Test func noActivePlanMeansNoPhaseRead() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: "[]")
        transport.enqueue(status: 200, json: habitRows)
        transport.enqueue(status: 200, json: "[]")
        let (backend, _) = make(transport)
        let plan = try await backend.habitPlan(patientId: "p-1", day: "2026-09-25", since: "2026-07-18")
        #expect(plan.header == nil)
        #expect(plan.phases.isEmpty)
        #expect(transport.requests.count == 3)
    }

    @Test func aCheckOffIsAPatientLoggedRowForTheDay_andAnUndoDeletesIt() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 201, json: #"[{"id":"c-9"}]"#)
        transport.enqueue(status: 204, json: "")
        let (backend, _) = make(transport)

        let at = Date(timeIntervalSince1970: 1_790_330_000)
        let id = try await backend.completeHabit(patientId: "p-1", habitId: "h-1", day: "2026-09-25", at: at)
        #expect(id == "c-9")
        let insert = try #require(transport.requests.first)
        #expect(insert.method == .post)
        #expect(insert.url.path.hasSuffix("/rest/v1/habit_completions"))
        #expect(insert.headers["Prefer"] == "return=representation")
        let body = try json(insert)
        #expect(body["habit_id"] as? String == "h-1")
        #expect(body["patient_id"] as? String == "p-1")
        #expect(body["completion_date"] as? String == "2026-09-25")
        #expect(body["logged_by"] as? String == "patient")       // the RLS insert policy requires it
        #expect((body["completed_at"] as? String)?.hasPrefix("2026-09-25T") == true)

        try await backend.deleteHabitCompletion(id: "c-9")
        let delete = transport.requests[1]
        #expect(delete.method == .delete)
        #expect(delete.url.path.hasSuffix("/rest/v1/habit_completions"))
        #expect(delete.url.query?.contains("id=eq.c-9") == true)
    }

    @Test func theGatePokeIsAPostWithTheDay() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"{"ok":true}"#)
        let (backend, _) = make(transport)
        try await backend.evaluateHabitGates(day: "2026-09-25")
        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/functions/v1/evaluate-gates"))
        #expect(try json(request)["today"] as? String == "2026-09-25")
    }

    @MainActor
    @Test func theServiceChecksOffOptimisticallyAndPutsItBackOnFailure() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: "[]")
        transport.enqueue(status: 200, json: habitRows)
        transport.enqueue(status: 200, json: "[]")
        let (backend, sessions) = make(transport)
        let auth = AuthService(sessions: sessions, state: AppState())
        let clock = Date(timeIntervalSince1970: 1_790_330_000)   // 2026-09-25 09:53 UTC — a morning
        let service = HabitsService(backend: backend, auth: auth, now: { clock }, calendar: {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
        }())

        await service.load(patientId: "p-1", day: "2026-09-25")
        #expect(service.plan?.habits.count == 2)
        #expect(service.actions.count == 2)
        #expect(service.actions.allSatisfy { !$0.done })

        // The write fails: the row shown at once is taken back.
        transport.enqueue(status: 500, json: #"{"message":"boom"}"#)
        let walk = try #require(service.actions.first { $0.id == "h-1" })
        await service.toggle(walk)
        #expect(service.actions.first { $0.id == "h-1" }?.done == false)
        #expect(service.plan?.completions.isEmpty == true)
        if case .loaded = service.phase {} else { Issue.record("a failed check-off must not fail the day") }

        // The write succeeds: the pending row takes the server's id, and undo deletes exactly that row.
        transport.enqueue(status: 201, json: #"[{"id":"c-9"}]"#)
        transport.enqueue(status: 200, json: #"{"ok":true}"#)   // the gate poke, if it lands before the undo
        await service.toggle(walk)
        let doneWalk = try #require(service.actions.first { $0.id == "h-1" })
        #expect(doneWalk.done)
        #expect(doneWalk.completionId == "c-9")
        transport.enqueue(status: 204, json: "")
        await service.toggle(doneWalk)
        #expect(service.actions.first { $0.id == "h-1" }?.done == false)
        let deletes = transport.requests.filter { $0.method == .delete }
        #expect(deletes.count == 1)
        #expect(deletes.first?.url.query?.contains("id=eq.c-9") == true)
    }
}
