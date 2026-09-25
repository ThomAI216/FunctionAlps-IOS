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
    /// `transcribe-audio` (Infomaniak Whisper, sovereign): base64 audio → the transcript ("" when nothing was heard).
    /// No language hint: Whisper detects it, so a member may speak French one day and English the next.
    func transcribeAudio(base64: String, mimeType: String) async throws -> String
    /// `preprocess-meal` (Infomaniak text model): the words → food items with grams; fillers dropped,
    /// names kept in the spoken language, questions in the app language.
    func preprocessMeal(transcript: String, mealType: String?, locale: String) async throws -> MealPreprocess
    func updateMealNote(mealId: String, note: String?) async throws
    func deleteMeal(id: String) async throws
    /// The day review re-slots a photo after its row was minted with the slot the order guessed.
    func updateMealType(mealId: String, mealType: MealLog.MealType) async throws
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
    /// PRD §41 — ONE writer: RPC `member_submit_checkin` upserts the moment, recomputes the day summary from every
    /// moment of the day and appends the events in one transaction; the patient is resolved from the JWT.
    /// RAW answers up, the SERVER-scored row back (`member_submit_checkin` v2) — one scorer for every client.
    func submitCheckin(day: String, slot: MomentSlot, submission: CheckinSubmission) async throws -> CheckinSubmitResult

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
    /// One `nb_meal_reactions` row — the Expo `saveMealReaction` shape (a row IS the "they answered" signal).
    func saveMealReaction(_ write: MealReactionWrite) async throws

    // MARK: Sign-up + onboarding (patient-register · nb_patient_app_profiles · confirm_member_adult)

    /// Edge fn `patient-register` — creates or links the patient row and stamps `user_metadata.patient_id`; returns the patient id.
    func registerPatient(firstName: String, lastName: String, email: String) async throws -> String
    /// `onboarding_completed_at` (only when still null — the first finish is the date) + `onboarding_source = 'app_baseline'`.
    func stampOnboardingComplete(patientId: String) async throws -> Date
    /// RPC `confirm_member_adult(p_date_of_birth)` — true when 18+ (and the row is stamped); under-age is refused locally first.
    func confirmAdult(dateOfBirth: String) async throws -> Bool
    /// RPC `confirm_member_adult_from_record()` — answers 18+ from the CLINICAL record's date of birth,
    /// so a patient the dashboard already knows is never asked to retype it.
    /// true = confirmed and stamped · false = under age per the record · nil = no usable date on file.
    func confirmAdultFromRecord() async throws -> Bool?

    // MARK: Meal corrections (resolve-foods · nb_meal_logs update · nb_patient_food_aliases)

    /// Edge fn `resolve-foods` — the SAME pricing ladder `analyze-meal` uses, one row at a time, no language model.
    /// Nil on a transport failure or a shorter-than-asked answer (guessing the alignment would price rows off the wrong reference).
    func resolveFoods(_ requests: [MealEdit.PricingRequest]) async throws -> [MealEdit.ResolvedPricing]?
    /// The edited meal back onto its row: name, `ai_identified_foods`, totals, micros, the three scores (the Expo `updateSavedMeal`).
    func updateMealAnalysis(mealId: String, draft: MealDraft) async throws
    /// Which reference plane a resolved id lives in — generic `nb_food_items` or branded `nb_food_products`; nil = not storable.
    func foodAliasTarget(foodItemId: String) async throws -> FoodAliasTarget?
    /// Write or corroborate one learned food (read-then-write on the unique (patient, alias_norm) key).
    func upsertFoodAlias(_ row: FoodAliasRow) async throws -> FoodAliasWrite
    /// Live updates to ONE meal row (Supabase Realtime, `postgres_changes` UPDATE on `nb_meal_logs`, the member's
    /// own row under RLS). `onRow` gets each new snapshot; `onLifecycle` the channel's state. Never throws: a
    /// transport that cannot subscribe reports `.channelError` / `.closed` and the caller polls instead.
    func subscribeMeal(id: String, onRow: @escaping @Sendable (MealLog) -> Void, onLifecycle: @escaping @Sendable (RealtimeLifecycle) -> Void) -> RealtimeSubscription
    /// The member's own `nb_user_patterns` rows (the frx engine's nightly food × reaction patterns), newest first.
    func userPatterns(patientId: String) async throws -> [UserPattern]
    /// The member's active elimination protocols + per-member overrides (`nb_patient_protocols`, `nb_protocol_overrides`).
    func activeProtocols(patientId: String) async throws -> ProtocolData
    /// The practice's record for the baseline prefill: the four intake answers (`patient_intake_questionnaire.answers`
    /// gender / height_cm / weight_now / activity), when it was submitted, and `patients.date_of_birth` — the member's
    /// own session under RLS `intake_self_read` / `patients_self_select`. Nothing else leaves the questionnaire.
    func intakeBaseline(patientId: String) async throws -> IntakeBaselineRead?

    // MARK: Gut check-in (patient_daily_checkins gut_* + nb_checkin_events)

    /// Today's saved gut check-in (`gut_detail` + `intelligence_completed_at`), nil when not done today.
    func gutToday(patientId: String, day: String) async throws -> GutTodayRead?
    /// Days with a gut check-in in [since, before) (YYYY-MM-DD), oldest first — the 14-day dashboard.
    func gutHistory(patientId: String, since: String, before: String) async throws -> [GutDay]
    /// The Expo `saveGutCheckinV2` upsert on (patient_id, checkin_date); every listed column explicit.
    func upsertGutCheckin(patientId: String, day: String, write: GutCheckinWrite) async throws

    // MARK: Notifications (patient_notification_preferences — one row per member)

    func notificationPrefs(patientId: String) async throws -> NotificationPrefsRow?
    /// Upsert on `patient_id`; every preference column is written.
    func saveNotificationPrefs(_ row: NotificationPrefsRow) async throws
    /// The APNs token + device facts, upserted on `patient_id` (the preferences columns are untouched).
    func savePushToken(_ write: PushTokenWrite) async throws

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
    /// The targets page (nutrition-macros) — see `NutritionProfileWrite`.
    func saveNutritionProfile(patientId: String, profile: NutritionProfileWrite) async throws

    // MARK: Lab results (get_member_lab_results — CLINICAL migration 223)

    /// One row per marker line of the member's APPROVED lab releases, from the frozen release content.
    /// The patient is resolved from the JWT inside the function; nothing else about labs is readable.
    func labResults() async throws -> [LabResultRow]

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
    func recordConsents(_ decisions: [ConsentDecision], presentedKeys: [String], privacyNoticeVersion: String, locale: String, channel: String) async throws
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

    /// The sleep rows of the last couple of days, whatever wrote them — the morning check-in's prefill
    /// for a member whose wearable syncs server-side rather than through Apple Health on this phone.
    func wearableSleepRows(patientId: String, since: String) async throws -> [WearableNightRow]

    /// Today's focus (`member-daily-focus`). The day is computed once and then read back; `recompute`
    /// (sent after the morning check-in is saved or edited) recomputes it and retires what changed.
    /// `locale` (`en` · `fr`) picks the language the practice's texts come back in — English where no French is written.
    func dailyFocus(recompute: Bool, locale: String) async throws -> TodayFocus

    /// The member marked an offer done, or undid it. Today's rows only (the `habit_offers` update policy).
    func setFocusOfferCompleted(id: String, completed: Bool) async throws
    /// Devices linked through Thryve on the web app (`wearable_connections`, member-read RLS).
    func wearableConnections(patientId: String) async throws -> [WearableConnectionRow]
    // Direct vendors (wearable_vendors · wearable-oauth-start · wearable-vendor-disconnect · wearable-vendor-sync)
    func wearableVendors() async throws -> [WearableVendorRow]
    /// The member's own vendor accounts (status columns only; platform v2 nine states).
    func wearableVendorAccounts(patientId: String) async throws -> [WearableVendorAccountRow]
    func vendorConnectStart(vendor: String) async throws -> VendorConnectStart
    /// `erase` = the delete-my-data flow: the stored readings of that vendor are deleted as well.
    func vendorDisconnect(vendor: String, erase: Bool) async throws
    func vendorSyncNow() async throws
}

/// The `nb_meal_reactions` insert. Symptoms are 0–10 (a "fine" meal saves zeros); `overall` nil = unknown.
struct MealReactionWrite: Encodable, Sendable, Equatable {
    let patientId: String
    let mealLogId: String
    /// The headline: how the meal SAT (the digestion read). Everything downstream reads this column.
    let overall: Double?
    let bloating: Int
    let fullness: Int
    let gasBurden: Int
    /// Reflux, from the digestion pills.
    var burning: Int? = nil
    /// Crashed or sleepy, from the energy pills.
    var fatigue: Int? = nil
    /// The two reads that have their own column; focus has none and rides in `responses`.
    var digestion: Int? = nil
    var energy: Int? = nil
    let responses: [String: Double]?
    let reactionFlags: [String]?
    /// ISO 8601 (the encoder has no date strategy — `ISO8601.string`).
    let reactionTime: String
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
    /// The structured list from `preprocess-meal` — grams as a field, not a substring (`_shared/stated-items.ts`).
    var items: [StatedItem] = []
    /// Member-initiated do-over: the server re-reads stored photos and resets the attempt budget.
    var reanalyze: Bool = false
}

/// One food the member stated, as `analyze-meal` wants it.
struct StatedItem: Encodable, Sendable, Equatable {
    let name: String
    let grams: Int
    var volumeMeasure: String? = nil
    private enum CodingKeys: String, CodingKey { case name, grams, volumeMeasure = "volume_measure" }
}

/// What `preprocess-meal` extracted from the spoken or typed words.
struct MealPreprocess: Sendable, Equatable {
    struct Item: Sendable, Equatable, Identifiable {
        var name: String
        var quantity: String?
        var estimatedG: Int
        var volumeMeasure: String?
        var confidence: String
        var id: String { name + "|" + (quantity ?? "") }
        var stated: StatedItem? {
            let n = name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty, estimatedG > 0 else { return nil }
            let v = volumeMeasure?.trimmingCharacters(in: .whitespaces) ?? ""
            return StatedItem(name: n, grams: estimatedG, volumeMeasure: v.isEmpty ? nil : v)
        }
    }
    let language: String?
    let cleanedTranscript: String
    let items: [Item]
    /// The model's follow-up questions, typed (identity / quantity) — see `ClarificationLogic`.
    var clarifications: [MealClarification] = []
}

/// What the Protocol Lens needs from the backend, in one read.
struct ProtocolData: Sendable, Equatable {
    let protocols: [ProtocolLens.PatientProtocol]
    let overrides: [ProtocolLens.Override]
    static let none = ProtocolData(protocols: [], overrides: [])
}

/// Which reference plane a corrected food lives in. `ResolvedItem.food_item_id` carries an `nb_food_items` id for the
/// generic tiers and an `nb_food_products` id for branded rows; the alias table needs them stored differently.
enum FoodAliasTarget: Sendable, Equatable {
    case foodItem(id: String, name: String)
    case product(offCode: String, name: String)

    var name: String {
        switch self {
        case .foodItem(_, let n), .product(_, let n): n
        }
    }
}

/// One `nb_patient_food_aliases` row — the pipeline's name (normalised) → the food the member said it was.
struct FoodAliasRow: Sendable, Equatable {
    let patientId: String
    let aliasNorm: String
    let foodItemId: String?
    let offCode: String?
    let gramsDefault: Int?
    /// 'correction' (they changed it) | 'confirmation' (they kept it).
    let source: String
}

enum FoodAliasWrite: Sendable, Equatable { case inserted, corroborated }
