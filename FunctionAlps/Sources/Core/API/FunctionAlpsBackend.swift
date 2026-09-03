import Foundation

/// Domain operations the app needs. Implementations own the transport.
/// Today: `SupabaseBackend` (PostgREST + Edge Functions + Storage on CM OS).
/// Later: `GatewayBackend` for `api.functionalps.ch` — same protocol, no feature changes.
protocol FunctionAlpsBackend: Sendable {
    /// `patients.id` for the signed-in account, or nil when the account has no patient row yet.
    func currentPatientId() async throws -> String?
    func memberProfile(patientId: String) async throws -> MemberProfile?
    func meals(patientId: String, since: Date) async throws -> [MealLog]
    func dailyCheckin(patientId: String, day: String) async throws -> DailyCheckin?
    /// Day rows from `since` (YYYY-MM-DD) onward, oldest first — the Home history bars.
    func dailyCheckins(patientId: String, since: String) async throws -> [DailyCheckin]
    func unreadClinicianMessageCount(patientId: String) async throws -> Int

    // MARK: Meals (Phase D)

    func meal(id: String) async throws -> MealLog?
    /// Inserts the minimal `queued` row and returns its id. The meal is real from this moment;
    /// nothing analysis-derived is written by the client (the server owns every later status).
    func createPendingMeal(_ input: PendingMealInput) async throws -> String
    func attachMealPhotos(mealId: String, paths: [String]) async throws
    /// Asks the server to identify + price the meal and write the result onto the row.
    func analyzeMeal(_ request: AnalyzeMealRequest) async throws
    func updateMealNote(mealId: String, note: String?) async throws
    func deleteMeal(id: String) async throws
    /// Uploads a JPEG to the private bucket under the AUTH user's folder; returns the storage path.
    func uploadMealPhoto(userId: String, jpeg: Data) async throws -> String
    func mealPhotoURL(path: String) async throws -> URL
    func removeMealPhotos(paths: [String]) async throws

    // MARK: Check-in moments (Phase B)

    /// Today's saved moments, oldest first.
    func checkinMoments(patientId: String, day: String) async throws -> [CheckinMoment]
    /// One row per (patient, day, slot); re-saving a slot edits it.
    func upsertCheckinMoment(patientId: String, day: String, moment: CheckinMoment) async throws
    /// What the day row already holds (read before the summary write — no-wipe).
    func dailyCheckinCarry(patientId: String, day: String) async throws -> DailyCheckinCarry?
    func upsertDailySummary(patientId: String, day: String, patch: DaySummaryPatch) async throws
    func insertCheckinEvents(patientId: String, events: [CheckinEvent]) async throws
}

struct PendingMealInput: Sendable, Equatable {
    let patientId: String
    let mealType: MealLog.MealType
    let source: MealLog.Source
    /// The member's words for a text/voice meal (lands transiently in `name` so the server can retry).
    let description: String?
    let loggedAt: Date
}

struct AnalyzeMealRequest: Sendable, Equatable {
    let mealId: String
    /// Photo 1 first. One image is sent as the single-image body, N as `imageBase64s`.
    var imageBase64s: [String] = []
    var description: String? = nil
    /// Member-initiated do-over: the server re-reads stored photos and resets the attempt budget.
    var reanalyze: Bool = false
}
