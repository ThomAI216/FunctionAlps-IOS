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

    // MARK: Scores (server-side engine)

    /// `member-scores` for the signed-in member; `tzOffsetMinutes` = minutes east of UTC on this device.
    func memberScores(tzOffsetMinutes: Int) async throws -> MemberScores

    // MARK: Library (the members catalog, read under the member's own session)

    /// `member_library_stage()` — fail closed to `.lead` is the SERVICE's job; the backend reports what CM OS said.
    func libraryStage() async throws -> RelationshipStage
    /// Catalog + progress + list + access + priority + plan in one go; only the catalog read may throw.
    func libraryRaw(patientId: String) async throws -> LibraryRaw
    /// `member_library_get(p_slug)`; nil when the slug is unknown.
    func libraryItem(slug: String) async throws -> LibraryGetRow?
    /// `member_lesson_progress` insert (a nil track = a standalone-resource open).
    func insertLessonProgress(patientId: String, trackId: String?, contentSlug: String) async throws

    // MARK: Meal reactions

    /// The latest felt reaction for a meal (`nb_meal_reactions`), or nil when never rated.
    func mealReaction(mealId: String) async throws -> MealReaction?
    /// Reactions for every meal since `since`, keyed by meal id — the Food tab's "how it felt" lines.
    func mealReactions(patientId: String, since: Date) async throws -> [String: MealReaction]

    // MARK: Favorites + re-log (Food tab)

    func favorites(patientId: String) async throws -> [FavoriteMeal]
    func addFavorite(_ meal: MealLog, patientId: String) async throws -> FavoriteMeal
    func removeFavorite(id: String) async throws
    func touchFavorite(id: String) async throws
    /// Inserts a priced clone of `source` as a new meal logged now; returns its id.
    func relogMeal(_ source: RelogSource, patientId: String) async throws -> String

    // MARK: Profile tab

    /// The active `care_plans` row + its member-visible `care_plan_items` (RLS does the filtering);
    /// nil when nothing is published yet.
    func carePlan(patientId: String) async throws -> CarePlan?
    /// `member_entitlements` rows for the access-window strip (fail-open is the SERVICE's job).
    func entitlements(patientId: String) async throws -> [EntitlementRow]
    /// The five baseline inputs: UPDATE by `patient_id`, INSERT only when there is no row yet — never an
    /// upsert (the conflict column is not UPDATE-able for members). The DB trigger recomputes the targets.
    func saveBaseline(patientId: String, values: BaselineValues) async throws

    // MARK: Messaging (patient_messages)

    /// `patients.clinic_id` for the signed-in account (own-row RLS) — every sent message carries it.
    func memberClinicId(userId: String) async throws -> String?
    /// The member's whole thread, oldest first (RLS scopes it; the patient-readable columns only).
    func messages() async throws -> [PatientMessage]
    /// Inserts a patient-authored message and returns its id.
    func sendMessage(patientId: String, clinicId: String, body: String, context: MessageContext?) async throws -> String
    /// `message-notify` — tells the clinician; fail-soft, the 15-minute sweep re-notifies anyway.
    func notifyMessage(id: String) async throws
    /// `member_mark_messages_read()` — stamps every unread clinician message.
    func markMessagesRead() async throws

    // MARK: Account (feedback · consents · legal · data · deletion)

    /// `member-feedback` — the PRODUCT channel; the tier is stamped server-side.
    func sendFeedback(message: String, appVersion: String) async throws
    /// `delete-account` — immediate hard delete; the auth user is gone when this returns.
    func deleteAccount() async throws
    /// `member_pending_consents(p_locale, false)` — what to show and what is already accepted.
    func consents(locale: String) async throws -> [ConsentItem]
    /// `record_consent_batch` — one transaction for the sitting.
    func recordConsents(_ decisions: [ConsentDecision], presentedKeys: [String], privacyNoticeVersion: String, locale: String) async throws
    /// `revoke_consent(p_consent_key, 'app_privacy')` — refuses contract_core by design.
    func revokeConsent(key: String) async throws
    /// The current approved `consent_definitions` rows for these keys in this locale (notices + documents).
    func legalDocuments(keys: [String], locale: String) async throws -> [LegalDocument]
    /// `count(*)` of the member's rows in one table.
    func dataCount(table: String, patientId: String) async throws -> Int
    /// Every column of the member's rows in one table, as the raw JSON array (the export).
    func dataRows(table: String, patientId: String) async throws -> Data

    // MARK: Wearables (Apple Health on this phone → wearable-ingest)

    /// `wearable-ingest`: the raw submission is stored verbatim, the rows upserted on their natural keys.
    func ingestWearable(_ batch: WearableBatch) async throws -> WearableIngestResult
    /// The member's own `wearable_daily_labeled` rows from `since` (YYYY-MM-DD), any source.
    func wearableDaily(patientId: String, since: String) async throws -> [WearableLabeledRow]
    /// Devices linked through Thryve on the web app (`wearable_connections`, member-read RLS).
    func wearableConnections(patientId: String) async throws -> [WearableConnectionRow]
}

/// One consent decision in a sitting (`record_consent_batch.p_decisions[]`).
struct ConsentDecision: Encodable, Sendable, Equatable {
    let key: String
    let version: String
    let granted: Bool
    let defaultState: Bool
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
