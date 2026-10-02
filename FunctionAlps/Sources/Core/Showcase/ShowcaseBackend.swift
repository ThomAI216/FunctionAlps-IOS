#if DEBUG
import Foundation

/// Answers every backend call from `ShowcaseData` — the screenshot build's whole world. No network, no CM OS,
/// no real member: see `Showcase`. Writes are accepted and forgotten.
final class ShowcaseBackend: FunctionAlpsBackend, @unchecked Sendable {
    private let screen = Showcase.screen
    /// The "check-in done" screenshot: today's evening moment is in.
    private var eveningDone: Bool { screen == .checkinDone }

    func currentPatientId() async throws -> String? { ShowcaseData.patientId }
    func memberProfile(patientId: String) async throws -> MemberProfile? { ShowcaseData.profile(onboarded: screen != .onboarding) }
    func meals(patientId: String, since: Date) async throws -> [MealLog] { ShowcaseData.meals(since: since) }
    func dailyCheckin(patientId: String, day: String) async throws -> DailyCheckin? { ShowcaseData.dailyCheckins(includeToday: eveningDone).first { $0.day == day } }
    func unreadClinicianMessageCount(patientId: String) async throws -> Int { 1 }

    func meal(id: String) async throws -> MealLog? { ShowcaseData.meal(id: id) }
    func createPendingMeal(_ input: PendingMealInput) async throws -> String { "stub" }
    func attachMealPhotos(mealId: String, paths: [String]) async throws {}
    func transcribeAudio(base64: String, mimeType: String) async throws -> String { "" }
    func preprocessMeal(transcript: String, mealType: String?, locale: String) async throws -> MealPreprocess { MealPreprocess(language: nil, cleanedTranscript: transcript, items: []) }
    func analyzeMeal(_ request: AnalyzeMealRequest) async throws {}
    func updateMealNote(mealId: String, note: String?) async throws {}
    func deleteMeal(id: String) async throws {}
    func updateMealType(mealId: String, mealType: MealLog.MealType) async throws {}
    func uploadMealPhoto(userId: String, jpeg: Data) async throws -> String { "stub/photo.jpg" }
    func mealPhotoURL(path: String) async throws -> URL {
        if path.hasPrefix("https://"), let url = URL(string: path) { return url }
        return Bundle.main.url(forResource: "plate-demo", withExtension: "jpg") ?? URL(fileURLWithPath: "/dev/null")
    }
    func removeMealPhotos(paths: [String]) async throws {}
    func dailyCheckins(patientId: String, since: String) async throws -> [DailyCheckin] { ShowcaseData.dailyCheckins(includeToday: eveningDone).filter { $0.day >= since } }
    func memberScores(tzOffsetMinutes: Int) async throws -> MemberScores { guard let s = ShowcaseData.scores() else { throw AppError.notFound }; return s }
    func libraryStage() async throws -> RelationshipStage { .active }
    func libraryRaw(patientId: String) async throws -> LibraryRaw { ShowcaseData.libraryRaw() }
    func libraryItem(slug: String) async throws -> LibraryGetRow? { ShowcaseData.libraryItem(slug: slug) }
    func libraryTopicCovers() async throws -> [LibraryTopicCoverRow] { ShowcaseData.covers }
    func insertLessonProgress(patientId: String, trackId: String?, contentSlug: String) async throws {}
    func mealReaction(mealId: String) async throws -> MealReaction? { nil }
    func mealReactions(patientId: String, since: Date) async throws -> [String: MealReaction] { [:] }
    func saveMealReaction(_ write: MealReactionWrite) async throws {}
    func registerPatient(firstName: String, lastName: String, email: String) async throws -> RegisterOutcome { .patient(id: ShowcaseData.patientId) }
    func stampOnboardingComplete(patientId: String) async throws -> Date { Date() }
    func confirmAdult(dateOfBirth: String) async throws -> Bool { true }
    func confirmAdultFromRecord() async throws -> Bool? { true }
    func intakeBaseline(patientId: String) async throws -> IntakeBaselineRead? { nil }
    func resolveFoods(_ requests: [MealEdit.PricingRequest]) async throws -> [MealEdit.ResolvedPricing]? { [] }
    func updateMealAnalysis(mealId: String, draft: MealDraft) async throws {}
    func foodAliasTarget(foodItemId: String) async throws -> FoodAliasTarget? { nil }
    func upsertFoodAlias(_ row: FoodAliasRow) async throws -> FoodAliasWrite { .inserted }
    func userPatterns(patientId: String) async throws -> [UserPattern] { [] }
    func activeProtocols(patientId: String) async throws -> ProtocolData { .none }
    func subscribeMeal(id: String, onRow: @escaping @Sendable (MealLog) -> Void, onLifecycle: @escaping @Sendable (RealtimeLifecycle) -> Void) -> RealtimeSubscription { .inert }
    func gutToday(patientId: String, day: String) async throws -> GutTodayRead? { nil }
    func gutHistory(patientId: String, since: String, before: String) async throws -> [GutDay] { ShowcaseData.gutHistory().filter { $0.day >= since && $0.day < before } }
    func upsertGutCheckin(patientId: String, day: String, write: GutCheckinWrite) async throws {}
    func notificationPrefs(patientId: String) async throws -> NotificationPrefsRow? { nil }
    func saveNotificationPrefs(_ row: NotificationPrefsRow) async throws {}
    func savePushToken(_ write: PushTokenWrite) async throws {}
    func favorites(patientId: String) async throws -> [FavoriteMeal] { [] }
    func addFavorite(_ meal: MealLog, patientId: String) async throws -> FavoriteMeal { throw AppError.notFound }
    func removeFavorite(id: String) async throws {}
    func touchFavorite(id: String) async throws {}
    func relogMeal(_ source: RelogSource, patientId: String) async throws -> String { "relog" }

    func carePlan(patientId: String) async throws -> CarePlan? { ShowcaseData.carePlan }
    func labResults() async throws -> [LabResultRow] { [] }
    func entitlements(patientId: String) async throws -> [EntitlementRow] { [EntitlementRow(accessType: "full_access", status: "active", startsAt: nil, expiresAt: nil)] }
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
    func wearableSleepRows(patientId: String, since: String) async throws -> [WearableNightRow] { [] }
    func dailyFocus(recompute: Bool, locale: String) async throws -> TodayFocus { TodayFocus(day: ShowcaseData.day(0), needsCheckin: false, offers: []) }
    func habitPlan(patientId: String, day: String, since: String) async throws -> HabitPlan { ShowcaseData.habitPlan(day: day) }
    func completeHabit(patientId: String, habitId: String, day: String, at: Date) async throws -> String { "c-1" }
    func actionBank() async throws -> [ActionCardRow] { Array(ShowcaseData.cards.values).sorted { $0.id < $1.id } }
    func addOwnHabit(_ habit: OwnHabitInsert) async throws -> String { "h-own" }
    func removeOwnHabit(id: String) async throws {}
    func nextAppointment(after: Date) async throws -> AppointmentRow? { nil }
    func deleteHabitCompletion(id: String) async throws {}
    func evaluateHabitGates(day: String) async throws {}
    func setFocusOfferCompleted(id: String, completed: Bool) async throws {}
    func wearableConnections(patientId: String) async throws -> [WearableConnectionRow] { [] }
    func wearableVendors() async throws -> [WearableVendorRow] { [] }
    func vendorConnectStart(vendor: String) async throws -> VendorConnectStart { VendorConnectStart(url: URL(string: "https://example.test")!, vendor: vendor) }
    func wearableVendorAccounts(patientId: String) async throws -> [WearableVendorAccountRow] { [] }
    func vendorDisconnect(vendor: String, erase: Bool) async throws {}
    func vendorSyncNow() async throws {}
    func checkinMoments(patientId: String, day: String) async throws -> [CheckinMoment] { screen == .checkin || eveningDone ? [ShowcaseData.eveningMoment()] : [] }
    func upsertCheckinMoment(patientId: String, day: String, moment: CheckinMoment) async throws {}
    func dailyCheckinCarry(patientId: String, day: String) async throws -> DailyCheckinCarry? { nil }
    func upsertDailySummary(patientId: String, day: String, patch: DaySummaryPatch) async throws {}
    func insertCheckinEvents(patientId: String, events: [CheckinEvent]) async throws {}
    func submitCheckin(day: String, slot: MomentSlot, submission: CheckinSubmission) async throws -> CheckinSubmitResult {
        CheckinSubmitResult(moment: CheckinMoment(slot: slot, submittedAt: submission.submittedAt), momentCount: 1, scoredBy: "server", redFlags: .none)
    }
}
#endif
