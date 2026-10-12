import Foundation
import Testing
@testable import FunctionAlps

@Suite("The show's coming-soon switch (owner, 2026-10-06)")
struct ShowFeatureTests {
    private func backend(_ transport: MockTransport) -> SupabaseBackend {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store)
        let requester = AuthorizedRequester(sessions: sessions, transport: transport)
        return SupabaseBackend(
            rest: PostgRESTClient(environment: Fixtures.environment, requester: requester),
            functions: EdgeFunctionClient(environment: Fixtures.environment, requester: requester),
            storage: StorageClient(environment: Fixtures.environment, requester: requester),
            clinical: ClinicalAPIClient(baseURL: URL(string: "https://dashboard.example.com")!, sessions: sessions, transport: transport)
        )
    }

    @Test func presentation() {
        #expect(ShowFeature.presentation(comingSoon: true, hasData: true) == .comingSoon)
        #expect(ShowFeature.presentation(comingSoon: true, hasData: false) == .comingSoon)
        #expect(ShowFeature.presentation(comingSoon: false, hasData: true) == .live)
        #expect(ShowFeature.presentation(comingSoon: false, hasData: false) == .hidden)
        #expect(!ShowFeature.episodesReachable(comingSoon: true))
        #expect(ShowFeature.episodesReachable(comingSoon: false))
    }

    @Test func noReminderIsPlannedWhileComingSoon() {
        let state = ShowLogic.ExperimentState(done: [1, 2], nextDay: 3, doneToday: false)
        let now = ShowLogic.zonedDate(day: "2026-10-09", time: "08:00")!
        let cal = ShowLogic.calendar("Europe/Zurich")
        #expect(ShowFeature.reminderPlan(comingSoon: true, days: Array(1...7), state: state, now: now, calendar: cal).isEmpty)
        #expect(ShowFeature.reminderPlan(comingSoon: false, days: Array(1...7), state: state, now: now, calendar: cal).count == 5)
    }

    @Test func theCancelSetIsEveryShowReminderAndNothingElse() {
        let ids = ["show.exp.movement-1.3", "show.exp.sleep-2.1", "fa.checkin.evening.2026-10-06", "fa.meal.reaction.m1", "other"]
        #expect(ShowFeature.showReminderIDs(in: ids) == ["show.exp.movement-1.3", "show.exp.sleep-2.1"])
        #expect(ShowLogic.reminderPrefix == "show.exp.")
        #expect(ShowReminders.prefix == ShowLogic.reminderPrefix)
    }

    @Test func comingSoonCallsNothingAndWritesNothing() async {
        let transport = MockTransport()
        let shows = ShowService(backend: backend(transport), comingSoon: true)
        #expect(await shows.library() == nil)
        #expect(await shows.episode(slug: "movement-1") == .notFound)
        #expect(await shows.marks(patientId: "p1").isEmpty)
        #expect(await shows.markDay(patientId: "p1", slug: "movement-1", day: 1, dayNumbers: [1, 2, 3]) == .notAllowed)
        #expect(await shows.libraryState(patientId: "p1") == nil)
        #expect(transport.requestCount == 0)
    }

    @Test func switchedOffTheShowReadsClinicalWithTheMembersBearer() async throws {
        let transport = MockTransport()
        transport.enqueue(status: 200, json: #"{ "ok": true, "series": null, "episodes": [] }"#)
        let shows = ShowService(backend: backend(transport), comingSoon: false)
        let lib = try #require(await shows.library())
        #expect(lib.episodes.isEmpty)
        let request = try #require(transport.requests.first)
        #expect(request.url.absoluteString == "https://dashboard.example.com/api/webinars/library")
        #expect(request.headers["Authorization"] == "Bearer access-1")
    }
}
