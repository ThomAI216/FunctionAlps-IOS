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
    func transcribeAudio(base64: String, mimeType: String) async throws -> String { "" }
    func analyzeMeal(_ request: AnalyzeMealRequest) async throws {}
    func updateMealNote(mealId: String, note: String?) async throws {}
    func deleteMeal(id: String) async throws {}
    func uploadMealPhoto(userId: String, jpeg: Data) async throws -> String { "stub/photo.jpg" }
    func mealPhotoURL(path: String) async throws -> URL { URL(string: "https://example.invalid/\(path)")! }
    func removeMealPhotos(paths: [String]) async throws {}
    func dailyCheckins(patientId: String, since: String) async throws -> [DailyCheckin] { [] }
    func memberScores(tzOffsetMinutes: Int) async throws -> MemberScores { throw AppError.notFound }
    func libraryStage() async throws -> RelationshipStage { .lead }
    func libraryRaw(patientId: String) async throws -> LibraryRaw { throw AppError.notFound }
    func libraryItem(slug: String) async throws -> LibraryGetRow? { nil }
    func insertLessonProgress(patientId: String, trackId: String?, contentSlug: String) async throws {}
    func mealReaction(mealId: String) async throws -> MealReaction? { nil }
    func mealReactions(patientId: String, since: Date) async throws -> [String: MealReaction] { [:] }
    func saveMealReaction(_ write: MealReactionWrite) async throws {}
    var registerFails = false
    private(set) var registered: (first: String, last: String, email: String)?
    func registerPatient(firstName: String, lastName: String, email: String) async throws -> String {
        if registerFails { throw AppError.notFound }
        registered = (firstName, lastName, email)
        return "registered"
    }
    func stampOnboardingComplete(patientId: String) async throws -> Date { Date() }
    func confirmAdult(dateOfBirth: String) async throws -> Bool { true }
    func gutToday(patientId: String, day: String) async throws -> GutTodayRead? { nil }
    func gutHistory(patientId: String, since: String, before: String) async throws -> [GutDay] { [] }
    func upsertGutCheckin(patientId: String, day: String, write: GutCheckinWrite) async throws {}
    func notificationPrefs(patientId: String) async throws -> NotificationPrefsRow? { nil }
    func saveNotificationPrefs(_ row: NotificationPrefsRow) async throws {}
    func savePushToken(_ write: PushTokenWrite) async throws {}
    func favorites(patientId: String) async throws -> [FavoriteMeal] { [] }
    func addFavorite(_ meal: MealLog, patientId: String) async throws -> FavoriteMeal { throw AppError.notFound }
    func removeFavorite(id: String) async throws {}
    func touchFavorite(id: String) async throws {}
    func relogMeal(_ source: RelogSource, patientId: String) async throws -> String { "relog" }

    func carePlan(patientId: String) async throws -> CarePlan? { nil }
    func entitlements(patientId: String) async throws -> [EntitlementRow] { [] }
    func saveBaseline(patientId: String, values: BaselineValues) async throws {}
    func saveNutritionProfile(patientId: String, profile: NutritionProfileWrite) async throws {}
    func memberClinicId(userId: String) async throws -> String? { nil }
    func messages() async throws -> [PatientMessage] { [] }
    func sendMessage(patientId: String, clinicId: String, body: String, context: MessageContext?) async throws -> String { "msg" }
    func notifyMessage(id: String) async throws {}
    func markMessagesRead() async throws {}
    func sendFeedback(message: String, appVersion: String) async throws {}
    func deleteAccount() async throws {}
    func consents(locale: String) async throws -> [ConsentItem] { [] }
    func recordConsents(_ decisions: [ConsentDecision], presentedKeys: [String], privacyNoticeVersion: String, locale: String, channel: String) async throws {}
    func revokeConsent(key: String) async throws {}
    func legalDocuments(keys: [String], locale: String) async throws -> [LegalDocument] { [] }
    func dataCount(table: String, patientId: String) async throws -> Int { 0 }
    func dataRows(table: String, patientId: String) async throws -> Data { Data("[]".utf8) }
    func ingestWearable(_ batch: WearableBatch) async throws -> WearableIngestResult { WearableIngestResult(ok: true, rawEventId: nil, daily: batch.daily.count, epoch: batch.epoch.count, connection: nil) }
    func wearableDaily(patientId: String, since: String) async throws -> [WearableLabeledRow] { [] }
    func wearableConnections(patientId: String) async throws -> [WearableConnectionRow] { [] }
    func wearableVendors() async throws -> [WearableVendorRow] { [] }
    func vendorConnectStart(vendor: String) async throws -> VendorConnectStart { VendorConnectStart(url: URL(string: "https://example.test")!, vendor: vendor) }
    func vendorDisconnect(vendor: String) async throws {}
    func vendorSyncNow() async throws {}
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

    /// Third rung: no patient row → `patient-register` creates it and the id is remembered.
    @Test func registersWhenNoPatientRowExists() async throws {
        let (manager, store) = sessions(patientId: nil)
        let backend = StubBackend()
        let member = try await MemberService(sessions: manager, backend: backend).currentMember()
        #expect(member.patientId == "registered")
        #expect(try store.load()?.patientId == "registered")
        #expect(backend.registered?.email == "alex@example.com")
        // Names: no first_name metadata → the display name split.
        #expect(backend.registered?.first == "Alex")
    }

    @Test func unregisteredAccountIsSurfacedWhenRegistrationFails() async {
        let (manager, _) = sessions(patientId: nil)
        let backend = StubBackend()
        backend.registerFails = true
        await #expect(throws: MemberService.MemberError.notRegistered) {
            _ = try await MemberService(sessions: manager, backend: backend).currentMember()
        }
    }

    @Test func namesFallbackLadder() {
        let base = Fixtures.session(expiresAt: .distantFuture)
        var s = base; s.firstName = "Marie"; s.lastName = "Dupont"
        var n = MemberService.names(for: s)
        #expect(n.first == "Marie" && n.last == "Dupont")
        s = base; s.displayName = "Alex Martin Roe"
        n = MemberService.names(for: s)
        #expect(n.first == "Alex" && n.last == "Martin Roe")
        s = base; s.displayName = "Alex"
        n = MemberService.names(for: s)
        #expect(n.first == "Alex" && n.last == "Member")
        s = base; s.displayName = nil
        n = MemberService.names(for: s)
        #expect(n.first == "Member" && n.last == "Member")
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
