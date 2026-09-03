import Foundation

/// The one place that knows CM OS table, column, RPC and edge-function names.
/// Every query is the member's OWN rows under RLS (patient_id = their patients.id).
/// Column lists mirror the Expo app's selects (docs/audit/app-auth-data.md §3).
struct SupabaseBackend: FunctionAlpsBackend {
    private let rest: PostgRESTClient
    private let functions: EdgeFunctionClient
    private let storage: StorageClient

    init(rest: PostgRESTClient, functions: EdgeFunctionClient, storage: StorageClient) {
        self.rest = rest
        self.functions = functions
        self.storage = storage
    }

    // MARK: Identity

    func currentPatientId() async throws -> String? {
        try await rest.rpcScalar("current_member_patient_id", body: EmptyBody())
    }

    // MARK: Profile (nb_patient_app_profiles)

    private struct ProfileRow: Decodable, Sendable {
        let appSex: String?
        let appAge: Int?
        let appHeightCm: Double?
        let appWeightKg: Double?
        let activityLevel: String?
        let healthGoals: [String]?
        let currentComplaints: [String]?
        let dietaryPattern: String?
        let targetCalories: Int?
        let targetProteinG: Int?
        let targetCarbsG: Int?
        let targetFatG: Int?
        let goalMode: String?
        let onboardingCompletedAt: Date?
        let locale: String?
    }

    private static let profileColumns = [
        "app_sex", "app_age", "app_height_cm", "app_weight_kg", "activity_level",
        "health_goals", "current_complaints", "dietary_pattern",
        "target_calories", "target_protein_g", "target_carbs_g", "target_fat_g",
        "goal_mode", "onboarding_completed_at", "locale",
    ].joined(separator: ",")

    func memberProfile(patientId: String) async throws -> MemberProfile? {
        let row: ProfileRow? = try await rest.selectOne("nb_patient_app_profiles", query: [
            PG.select(Self.profileColumns),
            PG.eq("patient_id", patientId),
        ])
        guard let row else { return nil }
        return MemberProfile(
            sex: row.appSex.flatMap(MemberProfile.Sex.init(rawValue:)),
            age: row.appAge,
            heightCm: row.appHeightCm,
            weightKg: row.appWeightKg,
            activityLevel: row.activityLevel,
            healthGoals: row.healthGoals ?? [],
            currentComplaints: row.currentComplaints ?? [],
            dietaryPattern: row.dietaryPattern,
            targetCalories: row.targetCalories,
            targetProteinG: row.targetProteinG,
            targetCarbsG: row.targetCarbsG,
            targetFatG: row.targetFatG,
            goalMode: row.goalMode.flatMap(MemberProfile.GoalMode.init(rawValue:)),
            onboardingCompletedAt: row.onboardingCompletedAt,
            locale: row.locale
        )
    }

    // MARK: Meals (nb_meal_logs)

    /// Columns BY NAME, never `*`. `ai_coaching_response` is deliberately not read: it is model
    /// prose and must never sit next to `patient_note` under one label.
    private static let mealColumns = [
        "id", "logged_at", "meal_type", "name", "source", "analysis_status", "analysis_last_error",
        "total_calories", "total_protein_g", "total_carbs_g", "total_fat_g", "total_fiber_g",
        "photo_url", "photo_urls", "ai_identified_foods",
        "inflammation_score", "glycemic_score", "gut_score", "patient_note",
    ].joined(separator: ",")

    private struct MealRow: Decodable, Sendable {
        let id: String
        let loggedAt: Date
        let mealType: String?
        let name: String?
        let source: String?
        let analysisStatus: String?
        let analysisLastError: String?
        let totalCalories: Double?
        let totalProteinG: Double?
        let totalCarbsG: Double?
        let totalFatG: Double?
        let totalFiberG: Double?
        let photoUrl: String?
        let photoUrls: [String]?
        let aiIdentifiedFoods: [MealItem]?
        let inflammationScore: Double?
        let glycemicScore: Double?
        let gutScore: Double?
        let patientNote: String?

        private enum CodingKeys: String, CodingKey {
            case id, loggedAt, mealType, name, source, analysisStatus, analysisLastError
            case totalCalories, totalProteinG, totalCarbsG, totalFatG, totalFiberG
            case photoUrl, photoUrls, aiIdentifiedFoods, inflammationScore, glycemicScore, gutScore, patientNote
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            loggedAt = try c.decode(Date.self, forKey: .loggedAt)
            mealType = try c.decodeIfPresent(String.self, forKey: .mealType)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            source = try c.decodeIfPresent(String.self, forKey: .source)
            analysisStatus = try c.decodeIfPresent(String.self, forKey: .analysisStatus)
            analysisLastError = try c.decodeIfPresent(String.self, forKey: .analysisLastError)
            totalCalories = try c.decodeIfPresent(Double.self, forKey: .totalCalories)
            totalProteinG = try c.decodeIfPresent(Double.self, forKey: .totalProteinG)
            totalCarbsG = try c.decodeIfPresent(Double.self, forKey: .totalCarbsG)
            totalFatG = try c.decodeIfPresent(Double.self, forKey: .totalFatG)
            totalFiberG = try c.decodeIfPresent(Double.self, forKey: .totalFiberG)
            photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
            photoUrls = try? c.decodeIfPresent([String].self, forKey: .photoUrls)
            // jsonb the model wrote: an unexpected shape degrades to "no breakdown", never to a lost meal.
            aiIdentifiedFoods = try? c.decodeIfPresent([MealItem].self, forKey: .aiIdentifiedFoods)
            inflammationScore = try c.decodeIfPresent(Double.self, forKey: .inflammationScore)
            glycemicScore = try c.decodeIfPresent(Double.self, forKey: .glycemicScore)
            gutScore = try c.decodeIfPresent(Double.self, forKey: .gutScore)
            patientNote = try c.decodeIfPresent(String.self, forKey: .patientNote)
        }

        var model: MealLog {
            var scores: MealScores?
            if let i = inflammationScore, let g = glycemicScore, let d = gutScore {
                scores = MealScores(inflammation: Int(i.rounded()), glycemic: Int(g.rounded()), digestion: Int(d.rounded()))
            }
            return MealLog(
                id: id,
                loggedAt: loggedAt,
                mealType: mealType.flatMap(MealLog.MealType.init(rawValue:)),
                name: name,
                source: source.flatMap(MealLog.Source.init(rawValue:)),
                analysisStatus: analysisStatus.flatMap(MealLog.AnalysisStatus.init(rawValue:)),
                totalCalories: totalCalories,
                totalProteinG: totalProteinG,
                totalCarbsG: totalCarbsG,
                totalFatG: totalFatG,
                photoPaths: MealPhotoRef.paths(photoUrl: photoUrl, photoUrls: photoUrls),
                analysisError: analysisLastError,
                totalFiberG: totalFiberG,
                items: aiIdentifiedFoods ?? [],
                scores: scores,
                patientNote: patientNote
            )
        }
    }

    func meals(patientId: String, since: Date) async throws -> [MealLog] {
        let rows: [MealRow] = try await rest.select("nb_meal_logs", query: [
            PG.select(Self.mealColumns),
            PG.eq("patient_id", patientId),
            PG.gte("logged_at", ISO8601.string(since)),
            PG.order("logged_at", descending: true),
            PG.limit(100),
        ])
        return rows.map(\.model)
    }

    func meal(id: String) async throws -> MealLog? {
        let row: MealRow? = try await rest.selectOne("nb_meal_logs", query: [PG.select(Self.mealColumns), PG.eq("id", id)])
        return row?.model
    }

    /// ⚠ Keys must match live columns exactly: PostgREST rejects the WHOLE insert on an
    /// unknown column (PGRST204). Nothing analysis-derived goes in — a plausible zero would
    /// read as a fact in the clinical dashboards. Verified against CM OS 2026-09-03.
    private struct PendingMealBody: Encodable, Sendable {
        let patientId: String
        let loggedAt: String
        let mealType: String
        let source: String
        let name: String?
        let analysisStatus: String
    }

    private struct IdRow: Decodable, Sendable { let id: String }

    func createPendingMeal(_ input: PendingMealInput) async throws -> String {
        let words = input.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let row: IdRow = try await rest.insert("nb_meal_logs", body: PendingMealBody(
            patientId: input.patientId,
            loggedAt: ISO8601.string(input.loggedAt),
            mealType: input.mealType.rawValue,
            source: input.source.rawValue,
            name: words.isEmpty ? nil : String(words.prefix(300)),
            analysisStatus: MealLog.AnalysisStatus.queued.rawValue
        ))
        return row.id
    }

    /// `photo_url` keeps element 0 and `photo_urls` the whole ordered set INCLUDING it.
    private struct PhotosBody: Encodable, Sendable {
        let photoUrl: String
        let photoUrls: [String]
    }

    func attachMealPhotos(mealId: String, paths: [String]) async throws {
        let clean = paths.filter { !$0.isEmpty }
        guard let first = clean.first else { return }
        try await rest.update("nb_meal_logs", query: [PG.eq("id", mealId)], body: PhotosBody(photoUrl: first, photoUrls: clean))
    }

    /// Edge-function body is camelCase. One image is the byte-identical single-image body the
    /// shipped Expo app sends; N images use `imageBase64s`.
    private struct AnalyzeBody: Encodable, Sendable {
        let imageBase64: String?
        let imageBase64s: [String]?
        let description: String?
        let mealLogId: String
        let reanalyze: Bool?
    }

    func analyzeMeal(_ request: AnalyzeMealRequest) async throws {
        let images = request.imageBase64s.filter { !$0.isEmpty }
        let body = AnalyzeBody(
            imageBase64: images.count == 1 ? images[0] : nil,
            imageBase64s: images.count > 1 ? images : nil,
            description: request.description,
            mealLogId: request.mealId,
            reanalyze: request.reanalyze ? true : nil
        )
        try await functions.invokeRaw("analyze-meal", body: body, snakeCase: false)
    }

    /// Explicit null clears the note (a synthesized encoder would drop the key instead).
    private struct NoteBody: Encodable, Sendable {
        let patientNote: String?
        let patientNoteUpdatedAt: String
        private enum CodingKeys: String, CodingKey { case patientNote, patientNoteUpdatedAt }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(patientNote, forKey: .patientNote)
            try c.encode(patientNoteUpdatedAt, forKey: .patientNoteUpdatedAt)
        }
    }

    func updateMealNote(mealId: String, note: String?) async throws {
        try await rest.update("nb_meal_logs", query: [PG.eq("id", mealId)], body: NoteBody(patientNote: note, patientNoteUpdatedAt: ISO8601.string(Date())))
    }

    func deleteMeal(id: String) async throws {
        try await rest.delete("nb_meal_logs", query: [PG.eq("id", id)])
    }

    // MARK: Meal photos (storage bucket meal-images, folder = auth uid)

    func uploadMealPhoto(userId: String, jpeg: Data) async throws -> String {
        let path = "\(userId)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        try await storage.upload(bucket: MealPhotoRef.bucket, path: path, data: jpeg, contentType: "image/jpeg")
        return path
    }

    func mealPhotoURL(path: String) async throws -> URL {
        try await storage.signedURL(bucket: MealPhotoRef.bucket, path: path, expiresIn: 3600)
    }

    func removeMealPhotos(paths: [String]) async throws {
        try await storage.remove(bucket: MealPhotoRef.bucket, paths: paths)
    }

    // MARK: Check-in moments (patient_checkin_moments → patient_daily_checkins → nb_checkin_events)

    private static let momentColumns = "slot,submitted_at,energy_body,energy_mind,energy_stability,energy_overall,mood_score,stress_score,sleep_overall,sleep_refreshed,sleep_duration_min,sleep_latency_band,sleep_wake_count,pills,note"

    private struct MomentRow: Decodable, Sendable {
        let slot: String
        let submittedAt: Date
        let energyBody: Int?
        let energyMind: Int?
        let energyStability: Int?
        let energyOverall: Int?
        let moodScore: Int?
        let stressScore: Int?
        let sleepOverall: Int?
        let sleepRefreshed: Int?
        let sleepDurationMin: Int?
        let sleepLatencyBand: String?
        let sleepWakeCount: String?
        let pills: [String: [String]]?
        let note: String?

        private enum CodingKeys: String, CodingKey {
            case slot, submittedAt, energyBody, energyMind, energyStability, energyOverall, moodScore, stressScore
            case sleepOverall, sleepRefreshed, sleepDurationMin, sleepLatencyBand, sleepWakeCount, pills, note
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            slot = try c.decode(String.self, forKey: .slot)
            submittedAt = try c.decode(Date.self, forKey: .submittedAt)
            energyBody = try c.decodeIfPresent(Int.self, forKey: .energyBody)
            energyMind = try c.decodeIfPresent(Int.self, forKey: .energyMind)
            energyStability = try c.decodeIfPresent(Int.self, forKey: .energyStability)
            energyOverall = try c.decodeIfPresent(Int.self, forKey: .energyOverall)
            moodScore = try c.decodeIfPresent(Int.self, forKey: .moodScore)
            stressScore = try c.decodeIfPresent(Int.self, forKey: .stressScore)
            sleepOverall = try c.decodeIfPresent(Int.self, forKey: .sleepOverall)
            sleepRefreshed = try c.decodeIfPresent(Int.self, forKey: .sleepRefreshed)
            sleepDurationMin = try c.decodeIfPresent(Int.self, forKey: .sleepDurationMin)
            sleepLatencyBand = try c.decodeIfPresent(String.self, forKey: .sleepLatencyBand)
            sleepWakeCount = try c.decodeIfPresent(String.self, forKey: .sleepWakeCount)
            // jsonb the client wrote: an odd shape degrades to "no pills", never to a lost moment.
            pills = try? c.decodeIfPresent([String: [String]].self, forKey: .pills)
            note = try c.decodeIfPresent(String.self, forKey: .note)
        }

        /// nil for a slot outside the vocabulary rather than letting it masquerade as a moment.
        var model: CheckinMoment? {
            guard let slot = MomentSlot(rawValue: slot) else { return nil }
            return CheckinMoment(
                slot: slot, submittedAt: submittedAt,
                energyBody: energyBody, energyMind: energyMind, energyStability: energyStability, energyOverall: energyOverall,
                moodScore: moodScore, stressScore: stressScore,
                sleepOverall: sleepOverall, sleepRefreshed: sleepRefreshed, sleepDurationMin: sleepDurationMin,
                sleepLatencyBand: sleepLatencyBand, sleepWakeCount: sleepWakeCount,
                pills: pills ?? [:], note: note
            )
        }
    }

    func checkinMoments(patientId: String, day: String) async throws -> [CheckinMoment] {
        let rows: [MomentRow] = try await rest.select("patient_checkin_moments", query: [
            PG.select(Self.momentColumns),
            PG.eq("patient_id", patientId),
            PG.eq("checkin_date", day),
            PG.order("submitted_at"),
        ])
        return rows.compactMap(\.model)
    }

    /// Every patient-written column, explicit nulls included: re-saving a slot REPLACES its answers.
    func upsertCheckinMoment(patientId: String, day: String, moment m: CheckinMoment) async throws {
        let row: ColumnPatch = [
            "patient_id": .string(patientId),
            "checkin_date": .string(day),
            "slot": .string(m.slot.rawValue),
            "submitted_at": .string(ISO8601.string(m.submittedAt)),
            "energy_body": .int(m.energyBody),
            "energy_mind": .int(m.energyMind),
            "energy_stability": .int(m.energyStability),
            "energy_overall": .int(m.energyOverall),
            "mood_score": .int(m.moodScore),
            "stress_score": .int(m.stressScore),
            "sleep_overall": .int(m.sleepOverall),
            "sleep_refreshed": .int(m.sleepRefreshed),
            "sleep_duration_min": .int(m.sleepDurationMin),
            "sleep_latency_band": .string(m.sleepLatencyBand),
            "sleep_wake_count": .string(m.sleepWakeCount),
            "pills": .pills(m.pills), // NOT NULL (default '{}') — always an object
            "note": .string(m.note),
        ]
        try await rest.upsert("patient_checkin_moments", onConflict: "patient_id,checkin_date,slot", body: row, snakeCase: false)
    }

    private struct CarryRow: Decodable, Sendable {
        let recovery: Int?
        let soreness: Int?
        let recentLoad: Int?
        let recentMentalLoad: Int?
        let energyBody: Int?
        let energyMind: Int?
        let energyStability: Int?
        let energyOverall: Int?
        let moodScore: Int?
        let stressScore: Int?
        let sleepOverall: Int?
        let sleepRefreshed: Int?
        let sleepDurationMin: Int?
        let sleepLatencyBand: String?
        let sleepWakeCount: String?
        let energy: Int?
        let mood: Int?
        let sleep: Int?
        let stress: Int?
    }

    private static let carryColumns = "recovery,soreness,recent_load,recent_mental_load,energy_body,energy_mind,energy_stability,energy_overall,mood_score,stress_score,sleep_overall,sleep_refreshed,sleep_duration_min,sleep_latency_band,sleep_wake_count,energy,mood,sleep,stress"

    func dailyCheckinCarry(patientId: String, day: String) async throws -> DailyCheckinCarry? {
        let row: CarryRow? = try await rest.selectOne("patient_daily_checkins", query: [
            PG.select(Self.carryColumns), PG.eq("patient_id", patientId), PG.eq("checkin_date", day),
        ])
        guard let r = row else { return nil }
        return DailyCheckinCarry(
            recovery: r.recovery, soreness: r.soreness, recentLoad: r.recentLoad, recentMentalLoad: r.recentMentalLoad,
            energyBody: r.energyBody, energyMind: r.energyMind, energyStability: r.energyStability, energyOverall: r.energyOverall,
            moodScore: r.moodScore, stressScore: r.stressScore,
            sleepOverall: r.sleepOverall, sleepRefreshed: r.sleepRefreshed, sleepDurationMin: r.sleepDurationMin,
            sleepLatencyBand: r.sleepLatencyBand, sleepWakeCount: r.sleepWakeCount,
            energy: r.energy, mood: r.mood, sleep: r.sleep, stress: r.stress
        )
    }

    /// `digestion` (gut territory) and `functional_detail` are never touched here.
    func upsertDailySummary(patientId: String, day: String, patch p: DaySummaryPatch) async throws {
        var row: ColumnPatch = [
            "patient_id": .string(patientId),
            "checkin_date": .string(day),
            "energy_body": .int(p.energyBody),
            "energy_mind": .int(p.energyMind),
            "energy_stability": .int(p.energyStability),
            "energy_overall": .int(p.energyOverall),
            "mood_score": .int(p.moodScore),
            "stress_score": .int(p.stressScore), // CALMNESS — never inverted
            "energy": .int(p.legacyEnergy),
            "mood": .int(p.legacyMood),
            "stress": .int(p.legacyStress),
            "recovery": .int(p.recovery),
            "soreness": .int(p.soreness),
            "recent_load": .int(p.recentLoad),
            "recent_mental_load": .int(p.recentMentalLoad),
            "functional_completed_at": .string(ISO8601.string(p.completedAt)),
            "completed_at": .string(ISO8601.string(p.completedAt)),
            "last_submission_form": .string("functional"),
        ]
        if let s = p.sleep {
            row["sleep_overall"] = .int(s.sleepOverall)
            row["sleep_refreshed"] = .int(s.sleepRefreshed)
            row["sleep_duration_min"] = .int(s.sleepDurationMin)
            row["sleep_latency_band"] = .string(s.sleepLatencyBand)
            row["sleep_wake_count"] = .string(s.sleepWakeCount)
            row["sleep"] = .int(s.legacySleep)
        }
        try await rest.upsert("patient_daily_checkins", onConflict: "patient_id,checkin_date", body: row, snakeCase: false)
    }

    private struct EventRow: Encodable, Sendable {
        let patientId: String
        let dimension: String
        let value: Int
        let source: String
        let ts: String
    }

    func insertCheckinEvents(patientId: String, events: [CheckinEvent]) async throws {
        guard !events.isEmpty else { return }
        let rows = events.map { EventRow(patientId: patientId, dimension: $0.dimension, value: $0.value, source: "daily", ts: ISO8601.string($0.ts)) }
        try await rest.insertRows("nb_checkin_events", body: rows)
    }

    // MARK: Daily check-in (patient_daily_checkins)

    private struct CheckinRow: Decodable, Sendable {
        let checkinDate: String
        let functionalCompletedAt: Date?
        let intelligenceCompletedAt: Date?
        // v2 0–100 markers (migration 070/071); legacy 1–10 columns as fallback
        let energyOverall: Int?
        let moodScore: Int?
        let sleepOverall: Int?
        let stressScore: Int?
        let gutOverall: Int?
        let energy: Int?
        let mood: Int?
        let sleep: Int?
        let stress: Int?
    }

    private static let checkinV2Columns = "checkin_date,functional_completed_at,intelligence_completed_at,energy_overall,mood_score,sleep_overall,stress_score,gut_overall,energy,mood,sleep,stress"
    private static let checkinLegacyColumns = "checkin_date,functional_completed_at,intelligence_completed_at,energy,mood,sleep,stress"

    func dailyCheckin(patientId: String, day: String) async throws -> DailyCheckin? {
        let base = [PG.eq("patient_id", patientId), PG.eq("checkin_date", day)]
        let row: CheckinRow?
        do {
            row = try await rest.selectOne("patient_daily_checkins", query: [PG.select(Self.checkinV2Columns)] + base)
        } catch AppError.validation {
            // PostgREST fails the whole select on an unknown column (pre-070 schema): retry legacy list.
            row = try await rest.selectOne("patient_daily_checkins", query: [PG.select(Self.checkinLegacyColumns)] + base)
        }
        return row.map(Self.checkin)
    }

    func dailyCheckins(patientId: String, since: String) async throws -> [DailyCheckin] {
        let base = [PG.eq("patient_id", patientId), PG.gte("checkin_date", since), PG.order("checkin_date"), PG.limit(60)]
        let rows: [CheckinRow]
        do {
            rows = try await rest.select("patient_daily_checkins", query: [PG.select(Self.checkinV2Columns)] + base)
        } catch AppError.validation {
            rows = try await rest.select("patient_daily_checkins", query: [PG.select(Self.checkinLegacyColumns)] + base)
        }
        return rows.map(Self.checkin)
    }

    /// Legacy 1–10 → 0–100 only when v2 is absent; stress legacy is "stress", v2 is calmness.
    private static func checkin(_ row: CheckinRow) -> DailyCheckin {
        func scaled(_ legacy: Int?) -> Int? { legacy.map { ($0 - 1) * 100 / 9 } }
        return DailyCheckin(
            day: row.checkinDate,
            functionalCompletedAt: row.functionalCompletedAt,
            gutCompletedAt: row.intelligenceCompletedAt,
            energy: row.energyOverall ?? scaled(row.energy),
            mood: row.moodScore ?? scaled(row.mood),
            sleep: row.sleepOverall ?? scaled(row.sleep),
            calmness: row.stressScore ?? row.stress.map { 100 - (($0 - 1) * 100 / 9) },
            gutOverall: row.gutOverall
        )
    }

    // MARK: Messages (patient_messages)

    func unreadClinicianMessageCount(patientId: String) async throws -> Int {
        try await rest.count("patient_messages", query: [
            PG.eq("patient_id", patientId),
            PG.eq("sender_type", "clinician"),
            URLQueryItem(name: "read_by_patient_at", value: "is.null"),
        ])
    }
}
