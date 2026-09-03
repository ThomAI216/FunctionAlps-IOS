import Foundation
import Testing
@testable import FunctionAlps

/// Backend double so service tests don't touch the wire.
final class StubBackend: FunctionAlpsBackend, @unchecked Sendable {
    var patientId: String?
    var profile: MemberProfile?
    var meals: [MealLog] = []
    var checkin: DailyCheckin?
    var unread = 0
    private(set) var patientIdCalls = 0

    func currentPatientId() async throws -> String? { patientIdCalls += 1; return patientId }
    func memberProfile(patientId: String) async throws -> MemberProfile? { profile }
    func meals(patientId: String, since: Date) async throws -> [MealLog] { meals }
    func dailyCheckin(patientId: String, day: String) async throws -> DailyCheckin? { checkin }
    func unreadClinicianMessageCount(patientId: String) async throws -> Int { unread }

    func meal(id: String) async throws -> MealLog? { meals.first { $0.id == id } }
    func createPendingMeal(_ input: PendingMealInput) async throws -> String { "stub" }
    func attachMealPhotos(mealId: String, paths: [String]) async throws {}
    func analyzeMeal(_ request: AnalyzeMealRequest) async throws {}
    func updateMealNote(mealId: String, note: String?) async throws {}
    func deleteMeal(id: String) async throws {}
    func uploadMealPhoto(userId: String, jpeg: Data) async throws -> String { "stub/photo.jpg" }
    func mealPhotoURL(path: String) async throws -> URL { URL(string: "https://example.invalid/\(path)")! }
    func removeMealPhotos(paths: [String]) async throws {}
    func dailyCheckins(patientId: String, since: String) async throws -> [DailyCheckin] { [] }
    func checkinMoments(patientId: String, day: String) async throws -> [CheckinMoment] { [] }
    func upsertCheckinMoment(patientId: String, day: String, moment: CheckinMoment) async throws {}
    func dailyCheckinCarry(patientId: String, day: String) async throws -> DailyCheckinCarry? { nil }
    func upsertDailySummary(patientId: String, day: String, patch: DaySummaryPatch) async throws {}
    func insertCheckinEvents(patientId: String, events: [CheckinEvent]) async throws {}
}

@Suite("MemberService")
struct MemberServiceTests {
    private func sessions(patientId: String?, displayName: String? = "Alex Ginsburg") -> (SessionManager, InMemorySessionStore) {
        let store = InMemorySessionStore(session: AuthSession(
            accessToken: "a", refreshToken: "r", expiresAt: .distantFuture,
            userId: "user-1", email: "alex@example.com", patientId: patientId, displayName: displayName
        ))
        let manager = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: MockTransport()), store: store)
        return (manager, store)
    }

    @Test func usesPatientIdFromSessionWithoutRPC() async throws {
        let (manager, _) = sessions(patientId: "p-from-jwt")
        let backend = StubBackend()
        let member = try await MemberService(sessions: manager, backend: backend).currentMember()
        #expect(member.patientId == "p-from-jwt")
        #expect(member.firstName == "Alex")
        #expect(backend.patientIdCalls == 0)
    }

    @Test func resolvesViaRPCAndRemembers() async throws {
        let (manager, store) = sessions(patientId: nil)
        let backend = StubBackend()
        backend.patientId = "p-from-rpc"
        let member = try await MemberService(sessions: manager, backend: backend).currentMember()
        #expect(member.patientId == "p-from-rpc")
        #expect(try store.load()?.patientId == "p-from-rpc")
    }

    @Test func unregisteredAccountIsSurfaced() async {
        let (manager, _) = sessions(patientId: nil)
        let backend = StubBackend()
        await #expect(throws: MemberService.MemberError.notRegistered) {
            _ = try await MemberService(sessions: manager, backend: backend).currentMember()
        }
    }

    @Test func fallsBackToEmailLocalPartForName() async throws {
        let (manager, _) = sessions(patientId: "p", displayName: nil)
        let member = try await MemberService(sessions: manager, backend: StubBackend()).currentMember()
        #expect(member.displayName == "alex")
    }
}

@Suite("DashboardService")
struct DashboardServiceTests {
    @Test func usesLocalCalendarDay() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // 2026-09-02 00:30 Zurich == 2026-09-01 22:30 UTC — must file under the 2nd.
        let now = Date(timeIntervalSince1970: 1_788_301_800)
        let backend = StubBackend()
        backend.unread = 2
        let service = DashboardService(backend: backend, calendar: calendar, now: { now })
        let today = try await service.today(patientId: "p")
        #expect(today.day == "2026-09-02")
        #expect(today.unreadClinicianMessages == 2)
        #expect(today.totalCalories == 0)
    }
}
