import Foundation

/// The Profile tab's reads and its one write: the care plan preview, the access window strip
/// (fail-open), and the baseline edit that re-runs the DB's energy trigger.
struct ProfileService: Sendable {
    private let backend: any FunctionAlpsBackend
    private let now: @Sendable () -> Date

    init(backend: any FunctionAlpsBackend, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.now = now
    }

    enum PlanState: Sendable, Equatable {
        case loading
        /// Nothing published yet — the honest waiting state.
        case none
        case plan(CarePlan)
    }

    /// Nil plan on any failure: the preview then shows the waiting copy rather than an error.
    func carePlan(patientId: String) async -> CarePlan? {
        try? await backend.carePlan(patientId: patientId)
    }

    /// FAIL-OPEN, deliberately: a read error is "allowed, unknown", never a countdown.
    func access(patientId: String) async -> AppAccess {
        guard let rows = try? await backend.entitlements(patientId: patientId) else { return .allowedUnknown }
        return AppAccess.resolve(rows, now: now())
    }

    /// Writes the inputs, then reads the profile back so the compass shows the trigger's number.
    func saveBaseline(patientId: String, values: BaselineValues) async throws -> MemberProfile? {
        try await backend.saveBaseline(patientId: patientId, values: values)
        return try? await backend.memberProfile(patientId: patientId)
    }

    /// The last onboarding screen's stamp (`onboarding_completed_at` + `onboarding_source='app_baseline'`).
    /// Returns the timestamp CM OS now holds — the gate trusts the row, never a local flag.
    func completeOnboarding(patientId: String) async throws -> Date {
        try await backend.stampOnboardingComplete(patientId: patientId)
    }

    /// The targets page's Validate: writes, then reads the row back so the page shows the trigger's targets.
    func saveNutritionProfile(patientId: String, profile: NutritionProfileWrite) async throws -> MemberProfile? {
        try await backend.saveNutritionProfile(patientId: patientId, profile: profile)
        return try? await backend.memberProfile(patientId: patientId)
    }
}

/// The in-app thread with the nutritionist (`patient_messages`), on the member's own session.
struct MessagingService: Sendable {
    private let backend: any FunctionAlpsBackend

    init(backend: any FunctionAlpsBackend) { self.backend = backend }

    func thread() async throws -> [PatientMessage] {
        try await backend.messages()
    }

    /// Sends, then notifies the clinician fail-soft (the 15-minute sweep re-notifies anything missed).
    func send(_ body: String, member: Member, context: MessageContext?) async throws {
        guard MessagingLogic.validate(body) else { throw AppError.validation(message: String(localized: "messages.empty", defaultValue: "Message cannot be empty.")) }
        guard let clinicId = try await backend.memberClinicId(userId: member.userId) else { throw AppError.notFound }
        let id = try await backend.sendMessage(patientId: member.patientId, clinicId: clinicId, body: body, context: context)
        try? await backend.notifyMessage(id: id)
    }

    func markRead() async {
        try? await backend.markMessagesRead()
    }
}

/// Feedback, consents, legal documents, the data summary/export and account deletion.
struct AccountService: Sendable {
    private let backend: any FunctionAlpsBackend

    init(backend: any FunctionAlpsBackend) { self.backend = backend }

    // MARK: Feedback (the PRODUCT channel — anything clinical belongs in Messages)

    func sendFeedback(_ message: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.validation(message: String(localized: "feedback.empty", defaultValue: "Please write something first.")) }
        try await backend.sendFeedback(message: trimmed, appVersion: AppInfo.version)
    }

    // MARK: Consents

    /// The 18+ check (`confirm_member_adult`): true = adult, recorded; false = refused server-side.
    /// Throws on anything else — an age check that could not run has not passed.
    func confirmAdult(dateOfBirth: String) async throws -> Bool {
        try await backend.confirmAdult(dateOfBirth: dateOfBirth)
    }

    struct ConsentsBundle: Sendable, Equatable {
        let consents: [ConsentItem]
        let notices: [LegalDocument]
        var groups: ConsentLogic.Groups { ConsentLogic.group(consents) }
        var preview: Bool { !consents.isEmpty && ConsentLogic.hasUnapprovedDrafts(consents) }
    }

    func consents() async throws -> ConsentsBundle {
        let locale = ConsentLogic.locale()
        async let ticks = backend.consents(locale: locale)
        let notices = (try? await backend.legalDocuments(keys: ConsentLogic.noticeKeys, locale: locale)) ?? []
        let ordered = ConsentLogic.noticeKeys.compactMap { key in notices.first { $0.consentKey == key } }
        return ConsentsBundle(consents: try await ticks, notices: ordered)
    }

    /// Grant an optional consent. NOTHING is optimistic: the caller re-reads afterwards.
    func grant(_ c: ConsentItem, in bundle: ConsentsBundle) async throws {
        try await backend.recordConsents(
            [ConsentDecision(key: c.consentKey, version: c.version, granted: true, defaultState: false)],
            presentedKeys: ConsentLogic.presentedKeys(bundle.consents, notices: bundle.notices),
            privacyNoticeVersion: ConsentLogic.privacyNoticeVersion(bundle.notices),
            locale: ConsentLogic.locale(),
            channel: "app_privacy"
        )
    }

    /// The first-launch gate: every decision in one transaction, channel `app_onboarding`.
    func recordGate(_ decisions: [ConsentDecision], in bundle: ConsentsBundle) async throws {
        try await backend.recordConsents(decisions, presentedKeys: ConsentLogic.presentedKeys(bundle.consents, notices: bundle.notices), privacyNoticeVersion: ConsentLogic.privacyNoticeVersion(bundle.notices), locale: ConsentLogic.locale(), channel: "app_onboarding")
    }

    func withdraw(_ c: ConsentItem) async throws {
        guard ConsentLogic.isWithdrawable(c) else { throw AppError.validation(message: "not withdrawable") }
        try await backend.revokeConsent(key: c.consentKey)
    }

    // MARK: Legal documents (read from CM OS — the wording has exactly one author)

    func legalDocument(key: String) async throws -> LegalDocument? {
        let locale = ConsentLogic.locale()
        if let doc = try await backend.legalDocuments(keys: [key], locale: locale).first { return doc }
        // A document not yet translated falls back to English rather than to nothing.
        guard locale != "en" else { return nil }
        return try await backend.legalDocuments(keys: [key], locale: "en").first
    }

    // MARK: Your data

    func dataSummary(member: Member) async -> DataSummary {
        let labels: [(String, String, String)] = [
            ("meals", "nb_meal_logs", String(localized: "data.meals", defaultValue: "Meals")),
            ("mealReactions", "nb_meal_reactions", String(localized: "data.mealReactions", defaultValue: "Meal reactions")),
            ("checkins", "patient_daily_checkins", String(localized: "data.checkins", defaultValue: "Check-ins")),
            ("checkinEvents", "nb_checkin_events", String(localized: "data.checkinEvents", defaultValue: "Check-in events")),
            ("assessments", "nb_assessment_responses", String(localized: "data.assessments", defaultValue: "Assessments")),
            ("reports", "nb_reports", String(localized: "data.reports", defaultValue: "Reports")),
            ("consents", "nb_app_consents", String(localized: "data.consents", defaultValue: "Consents")),
            ("patterns", "nb_user_patterns", String(localized: "data.patterns", defaultValue: "Patterns")),
        ]
        var counts: [DataSummary.Count] = []
        for (key, table, label) in labels {
            let n = (try? await backend.dataCount(table: table, patientId: member.patientId)) ?? 0
            counts.append(DataSummary.Count(key: key, label: label, value: n))
        }
        let since = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
        let meals = (try? await backend.meals(patientId: member.patientId, since: since)) ?? []
        let recent = meals.sorted { $0.loggedAt > $1.loggedAt }.prefix(3).map { DataSummary.RecentMeal(id: $0.id, name: $0.displayName, loggedAt: $0.loggedAt) }
        let profile = member.profile
        return DataSummary(
            profileName: member.firstName,
            age: profile?.age,
            sex: profile?.sex?.rawValue,
            goals: profile?.healthGoals ?? [],
            dietaryPattern: profile?.dietaryPattern,
            counts: counts,
            recentMeals: Array(recent)
        )
    }

    /// The whole bundle as one pretty JSON document — every table's rows exactly as CM OS returned them.
    func exportBundle(patientId: String) async -> Data {
        var out = "{\n  \"exportedAt\": \"\(ISO8601DateFormatter().string(from: Date()))\",\n  \"userId\": \"\(patientId)\""
        for entry in ExportTables.ordered {
            let raw = (try? await backend.dataRows(table: entry.table, patientId: patientId)) ?? Data("[]".utf8)
            var text = String(decoding: raw, as: UTF8.self)
            if entry.key == "profile" {
                // The profile is one object (or null), not an array.
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasPrefix("[") { text = String(text.dropFirst().dropLast()) }
                if text.isEmpty { text = "null" }
            }
            out += ",\n  \"\(entry.key)\": \(text)"
        }
        out += "\n}\n"
        return Data(out.utf8)
    }

    // MARK: Deletion

    func deleteAccount() async throws {
        try await backend.deleteAccount()
    }
}
