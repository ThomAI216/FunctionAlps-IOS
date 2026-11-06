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

    /// The practice's record for the baseline prefill — fail-soft: unreadable means "ask them", never a broken screen.
    func intakeBaseline(patientId: String) async -> IntakeBaselineRead? {
        try? await backend.intakeBaseline(patientId: patientId)
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

    /// The thread with the practice's resources and mini tracks under their messages. Both reads fail soft
    /// (the bubbles still show; the cards come back on the next load).
    func thread() async throws -> [PatientMessage] {
        async let resources = (try? backend.messageResources()) ?? []
        async let tracks = (try? backend.personalTracks()) ?? []
        let messages = try await backend.messages()
        let found = await tracks
        let withResources = MessagingLogic.attach(await resources, to: messages)
        return MessagingLogic.attach(tracks: found, to: withResources)
    }

    /// Who the member talks to (`member_care_team()`). Fails soft to an empty team (migration 288 may not be applied
    /// yet, or the read failed): every screen then keeps its "your nutritionist" wording and shows initials.
    func careTeam() async -> CareTeam {
        CareTeam(members: (try? await backend.careTeam()) ?? [])
    }

    /// The newest message of the thread (Home's quote), or nil. Fails soft.
    func lastMessage() async -> PatientMessage? {
        (try? await backend.messages())?.last
    }

    /// Sends. The practice is told by CLINICAL itself (its member-message alert reads `patient_messages`
    /// every five minutes, 2026-11-05); the app no longer calls `message-notify`, which never ran.
    func send(_ body: String, member: Member, context: MessageContext?) async throws {
        guard MessagingLogic.validate(body) else { throw AppError.validation(message: String(localized: "messages.empty", defaultValue: "Message cannot be empty.")) }
        guard let clinicId = try await backend.memberClinicId(userId: member.userId) else { throw AppError.notFound }
        _ = try await backend.sendMessage(patientId: member.patientId, clinicId: clinicId, body: body, context: context)
    }

    /// The member opened a resource card: stamp it once, fail-soft (the open is a courtesy to the practice,
    /// never a gate on reading).
    func markResourceOpened(id: String) async {
        _ = try? await backend.markMessageResourceOpened(id: id)
    }

    /// What the practice sent loose with messages (no personal track), for the Library's Pathway card.
    func sentResources() async -> [MessageResource] {
        async let resources = (try? backend.messageResources()) ?? []
        async let tracks = (try? backend.personalTracks()) ?? []
        return MessagingLogic.sentForLibrary(PersonalTrackLogic.looseResources(await resources, tracks: await tracks))
    }

    /// The personal mini tracks for the Library cards; fails soft to none.
    func personalTracks() async -> [PersonalTrack] {
        (try? await backend.personalTracks()) ?? []
    }

    /// Slugs the member has opened (for the "N new" on a track card); fails soft to none.
    func openedSlugs() async -> Set<String> {
        guard let patientId = try? await backend.currentPatientId() else { return [] }
        return (try? await backend.openedLibrarySlugs(patientId: patientId)) ?? []
    }

    /// One track for its page, with what it needs to draw: titles and what is opened. The track read throws (the page
    /// has an error state); titles and opens fail soft (a title falls back to the slug, nothing shows opened).
    func personalTrackPage(id: String) async throws -> PersonalTrackPage? {
        let backend = self.backend
        let tracks = try await backend.personalTracks()
        guard let track = tracks.first(where: { $0.id == id }) else { return nil }
        async let opened: Set<String> = {
            guard let patientId = try? await backend.currentPatientId() else { return [] }
            return (try? await backend.openedLibrarySlugs(patientId: patientId)) ?? []
        }()
        async let cards = (try? await backend.ladderCards()) ?? []
        var titles: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for slug in track.items.compactMap(\.slug) {
                group.addTask { (slug, (try? await backend.libraryItem(slug: slug))?.title) }
            }
            for await (slug, title) in group { if let title, !title.isEmpty { titles[slug] = title } }
        }
        let locale = TodayFocus.locale()
        for card in await cards { titles["action:" + card.id] = ActionCardLogic.content(card: card, habit: nil, locale: locale).title }
        return PersonalTrackPage(track: track, titles: titles, openedSlugs: await opened)
    }

    /// "Your Pathway": what grounds it. Each read fails soft (a missing part drops out of the sentence).
    func pathwayIntro(patientId: String, items: [MessageResource], now: Date = Date()) async -> PathwayIntro {
        async let consultation = try? backend.lastAppointment(before: now)
        async let objective = try? backend.activePlanObjective(patientId: patientId)
        // `try?` flattens the optional (Swift 5+): both are plain optionals here.
        let lastConsultation: AppointmentRow? = await consultation
        let objectiveLine: String? = await objective
        return PathwayLogic.intro(consultation: lastConsultation?.start, sentAt: items.map(\.createdAt), objective: objectiveLine)
    }

    /// Sent and never opened (loose sends, then articles of personal tracks) — the Library tab's badge and the
    /// Home nudge. Fails soft to 0.
    func unopenedSentCount() async -> Int {
        async let resources = (try? backend.messageResources()) ?? []
        async let tracks = (try? backend.personalTracks()) ?? []
        let found = await tracks
        let loose = PersonalTrackLogic.looseResources(await resources, tracks: found)
        let looseCount = MessagingLogic.unopenedCount(loose)
        guard !found.isEmpty, let patientId = try? await backend.currentPatientId() else { return looseCount }
        let opened = (try? await backend.openedLibrarySlugs(patientId: patientId)) ?? []
        let counted = Set(MessagingLogic.sentForLibrary(loose).map(\.slug))
        return looseCount + PersonalTrackLogic.unopenedCount(found, openedSlugs: opened, alreadyCounted: counted)
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

    /// The same check, answered from the clinical record instead of from the member
    /// (`confirm_member_adult_from_record`): true = adult, recorded; false = refused; nil = nothing on
    /// file to answer with, so the question still has to be asked.
    func confirmAdultFromRecord() async throws -> Bool? {
        try await backend.confirmAdultFromRecord()
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
