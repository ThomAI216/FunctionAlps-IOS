import Foundation
import Testing
@testable import FunctionAlps

@Suite("SupabaseBackend — today's focus (member-daily-focus · habit_offers)")
struct FocusBackendTests {
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

    /// The edge function's reply, as `member-daily-focus` shapes it.
    private let reply = """
    {"day":"2026-09-25","needsCheckin":false,"offers":[
      {"id":"o1","offerKey":"state:stressed:three_slow_breaths","rank":1,"title":"Three slow breaths, three times today",
       "description":"Before meals works well.","pillar":null,"slot":null,"variant":"easy","reason":"state",
       "trigger":"stressed","stateTitle":"A two-minute reset","accepted":null,"completed":false},
      {"id":"o2","offerKey":"bank:sit","rank":2,"title":"Five sit-to-stands","description":null,"pillar":"exercise",
       "slot":"midday","variant":"easy","reason":"readiness_low","trigger":"prio_train","stateTitle":null,
       "accepted":true,"completed":true}
    ]}
    """

    @Test func decodesTheDayAndAsksTheRightFunction() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: reply)
        let focus = try await make(transport).dailyFocus(recompute: true, locale: "fr")

        #expect(focus.day == "2026-09-25")
        #expect(!focus.needsCheckin)
        #expect(focus.focus?.title == "Three slow breaths, three times today")
        #expect(focus.focus?.stateTitle == "A two-minute reset")
        #expect(focus.focus?.reasonKind == .state)
        #expect(focus.focus?.accepted == nil)
        #expect(focus.alsoToday.count == 1)
        let train = try #require(focus.alsoToday.first)
        #expect(train.reasonKind == .readinessLow)
        #expect(train.pillarValue == .exercise)
        #expect(train.priority?.key == "prio_train")   // the morning's own priority pill, with its localised label
        #expect(train.completed)

        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/functions/v1/member-daily-focus"))
        #expect(try json(request)["recompute"] as? Bool == true)
        #expect(try json(request)["locale"] as? String == "fr")
    }

    @Test func noCheckinYetDecodesEmpty() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"{"day":"2026-09-25","needsCheckin":true,"offers":[]}"#)
        let focus = try await make(transport).dailyFocus(recompute: false, locale: "en")
        #expect(focus.needsCheckin)
        #expect(focus.focus == nil)
        #expect(try json(try #require(transport.requests.first))["recompute"] as? Bool == false)
    }

    @Test func asksInTheLanguageTheAppIsDrawnIn() {
        #expect(TodayFocus.locale(["fr"]) == "fr")
        #expect(TodayFocus.locale(["fr-CH", "en"]) == "fr")
        #expect(TodayFocus.locale(["en"]) == "en")
        #expect(TodayFocus.locale(["Base"]) == "en")
        #expect(TodayFocus.locale([]) == "en")
    }

    @Test func aStateTriggerIsNotMistakenForAPriority() throws {
        let data = Data(reply.utf8)
        let focus = try JSON.decode(TodayFocus.self, from: data)
        #expect(focus.focus?.priority == nil)   // "stressed" is a state, not a day_priority pill
    }

    @Test func doneAcceptsToo_undoLeavesTheAcceptanceAlone() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 204, json: "")
        transport.enqueue(status: 204, json: "")
        let backend = make(transport)
        try await backend.setFocusOfferCompleted(id: "o1", completed: true)
        try await backend.setFocusOfferCompleted(id: "o1", completed: false)

        let done = try #require(transport.requests.first)
        #expect(done.method == .patch)
        #expect(done.url.path.hasSuffix("/rest/v1/habit_offers"))
        #expect(done.url.query?.contains("id=eq.o1") == true)
        let doneBody = try json(done)
        #expect(doneBody["completed"] as? Bool == true)
        #expect(doneBody["accepted"] as? Bool == true)

        let undoBody = try json(transport.requests[1])
        #expect(undoBody["completed"] as? Bool == false)
        #expect(undoBody["accepted"] == nil)            // never written back as "declined"
    }
}
