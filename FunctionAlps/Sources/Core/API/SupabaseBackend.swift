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
        let tdeeKcal: Double?
        let estimatedBodyFatPercent: Double?
        let customCalorieOffsetKcal: Int?
        let mealsPerDay: Int?
        let snacksPerDay: Int?
        let macrosCustomized: Bool?
    }

    private static let profileColumns = [
        "app_sex", "app_age", "app_height_cm", "app_weight_kg", "activity_level",
        "health_goals", "current_complaints", "dietary_pattern",
        "target_calories", "target_protein_g", "target_carbs_g", "target_fat_g",
        "goal_mode", "onboarding_completed_at", "locale", "tdee_kcal",
        "estimated_body_fat_percent", "custom_calorie_offset_kcal", "meals_per_day", "snacks_per_day", "macros_customized",
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
            locale: row.locale,
            tdeeKcal: row.tdeeKcal,
            estimatedBodyFatPercent: row.estimatedBodyFatPercent,
            customCalorieOffsetKcal: row.customCalorieOffsetKcal,
            mealsPerDay: row.mealsPerDay,
            snacksPerDay: row.snacksPerDay,
            macrosCustomized: row.macrosCustomized ?? false
        )
    }

    // MARK: Meals (nb_meal_logs)

    /// Columns BY NAME, never `*`. `ai_coaching_response` is deliberately not read: it is model
    /// prose and must never sit next to `patient_note` under one label.
    private static let mealColumns = [
        "id", "logged_at", "meal_type", "name", "source", "analysis_status", "analysis_last_error",
        "total_calories", "total_protein_g", "total_carbs_g", "total_fat_g", "total_fiber_g",
        "photo_url", "photo_urls", "ai_identified_foods",
        "inflammation_score", "glycemic_score", "gut_score", "patient_note", "micronutrient_totals",
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
        let micronutrientTotals: [String: Double]

        private enum CodingKeys: String, CodingKey {
            case id, loggedAt, mealType, name, source, analysisStatus, analysisLastError
            case totalCalories, totalProteinG, totalCarbsG, totalFatG, totalFiberG
            case photoUrl, photoUrls, aiIdentifiedFoods, inflammationScore, glycemicScore, gutScore, patientNote, micronutrientTotals
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
            // jsonb the model wrote; a null value or an odd shape degrades to "no micros", never to a lost meal.
            micronutrientTotals = ((try? c.decodeIfPresent([String: Double?].self, forKey: .micronutrientTotals)) ?? nil)?.compactMapValues { $0 } ?? [:]
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
                patientNote: patientNote,
                micros: micronutrientTotals
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

    // MARK: Scores (edge function member-scores)

    private struct ScoresBody: Encodable, Sendable { let tzOffsetMinutes: Int }

    func memberScores(tzOffsetMinutes: Int) async throws -> MemberScores {
        try await functions.invoke("member-scores", body: ScoresBody(tzOffsetMinutes: tzOffsetMinutes), snakeCase: false)
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

    // MARK: Library (library_tracks / library_track_lessons / member_lesson_progress / RPCs)

    private struct EmptyBody: Encodable, Sendable {}
    private struct SlugBody: Encodable, Sendable { let pSlug: String }
    private struct AccessRow: Decodable, Sendable { let tracksEnabled: Bool?; let foundationsEnabled: Bool?; let supplementsEnabled: Bool? }
    private struct PriorityRow: Decodable, Sendable { let trackId: String }
    private struct GoalRow: Decodable, Sendable { let statement: String? }
    private struct ProgressBody: Encodable, Sendable { let patientId: String; let trackId: String?; let contentSlug: String }

    func libraryStage() async throws -> RelationshipStage {
        let raw = try await rest.rpcScalar("member_library_stage", body: EmptyBody())
        return raw.flatMap(RelationshipStage.init(rawValue:)) ?? .lead
    }

    /// A read that may fail without taking the library down.
    private func soft<T: Sendable>(_ op: @Sendable () async throws -> T) async -> T? {
        try? await op()
    }

    func libraryRaw(patientId: String) async throws -> LibraryRaw {
        let rest = self.rest
        async let tracks: [LibraryRawTrack] = rest.select("library_tracks", query: [
            PG.select("id,slug,title,description,pillar,cover_style,position,requires_stage,requires_track_id"), PG.order("position"),
        ])
        async let lessons = soft { () -> [LibraryRawLesson] in
            try await rest.select("library_track_lessons", query: [PG.select("track_id,position,content_slug"), PG.order("position")])
        }
        async let progress = soft { () -> [LibraryRawProgress] in
            try await rest.select("member_lesson_progress", query: [PG.select("track_id,content_slug"), PG.eq("patient_id", patientId)])
        }
        async let list = soft { () -> [LibraryListRow] in
            try await rest.rpc("member_library_list", body: EmptyBody())
        }
        async let access = soft { () -> AccessRow? in
            try await rest.selectOne("member_library_access", query: [PG.select("tracks_enabled,foundations_enabled,supplements_enabled"), PG.eq("patient_id", patientId)])
        }
        async let priority = soft { () -> [PriorityRow] in
            try await rest.select("patient_track_priority", query: [PG.select("track_id,position"), PG.eq("patient_id", patientId), PG.order("position")])
        }
        async let plan = soft { () -> LibraryRawPlan? in
            try await rest.selectOne("care_plans", query: [
                PG.select("id,title,start_date"), PG.eq("patient_id", patientId), PG.eq("status", "active"), PG.order("created_at", descending: true), PG.limit(1),
            ])
        }

        var raw = LibraryRaw()
        raw.tracks = try await tracks
        raw.lessons = await lessons ?? []
        raw.progress = await progress ?? []
        raw.list = await list ?? []
        if let row = await access ?? nil {
            raw.access = LibraryAccess(tracks: row.tracksEnabled == true, foundations: row.foundationsEnabled == true, supplements: row.supplementsEnabled == true)
        }
        raw.priorityTrackIds = (await priority ?? []).map(\.trackId)
        if let planRow = await plan ?? nil {
            raw.plan = planRow
            // Objectives arrive in a second read so a goals failure cannot take the plan title down with it.
            let goals = await soft { () -> [GoalRow] in
                try await rest.select("care_plan_goals", query: [
                    PG.select("statement,sort_order"), PG.eq("care_plan_id", planRow.id),
                    URLQueryItem(name: "visibility_class", value: "in.(patient_visible,patient_visible_after_approval)"),
                    PG.order("sort_order"),
                ])
            }
            raw.planObjectives = (goals ?? []).compactMap(\.statement).filter { !$0.isEmpty }
        }
        return raw
    }

    func libraryItem(slug: String) async throws -> LibraryGetRow? {
        let rows: [LibraryGetRow] = try await rest.rpc("member_library_get", body: SlugBody(pSlug: slug))
        return rows.first
    }

    func insertLessonProgress(patientId: String, trackId: String?, contentSlug: String) async throws {
        try await rest.insertRows("member_lesson_progress", body: [ProgressBody(patientId: patientId, trackId: trackId, contentSlug: contentSlug)])
    }

    // MARK: Meal reactions (nb_meal_reactions)

    private struct ReactionRow: Decodable, Sendable { let overall: Double?; let reactionFlags: [String]? }

    func mealReaction(mealId: String) async throws -> MealReaction? {
        let row: ReactionRow? = try await rest.selectOne("nb_meal_reactions", query: [
            PG.select("overall,reaction_flags"), PG.eq("meal_log_id", mealId), PG.order("reaction_time", descending: true), PG.limit(1),
        ])
        return row.map { MealReaction(overall: $0.overall, flags: $0.reactionFlags ?? []) }
    }


    // MARK: Favorites (nb_favorite_meals) + re-log — the Expo `favorites.ts` / `buildRelogRow` shapes

    private static let favoriteColumns = "id,name,meal_type,source,items,total_calories,total_protein_g,total_carbs_g,total_fat_g,total_fiber_g,micronutrient_totals,inflammation_score,glycemic_score,gut_score,photo_url,source_meal_log_id,created_at,last_used_at"

    private struct FavoriteRow: Decodable, Sendable {
        let id: String
        let name: String?
        let mealType: String?
        let source: String?
        let items: [MealItem]?
        let totalCalories: Double?
        let totalProteinG: Double?
        let totalCarbsG: Double?
        let totalFatG: Double?
        let totalFiberG: Double?
        let micronutrientTotals: [String: Double?]?
        let inflammationScore: Double?
        let glycemicScore: Double?
        let gutScore: Double?
        let photoUrl: String?
        let sourceMealLogId: String?
        let createdAt: Date?
        let lastUsedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case id, name, mealType, source, items, totalCalories, totalProteinG, totalCarbsG, totalFatG, totalFiberG
            case micronutrientTotals, inflammationScore, glycemicScore, gutScore, photoUrl, sourceMealLogId, createdAt, lastUsedAt
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            mealType = try? c.decodeIfPresent(String.self, forKey: .mealType)
            source = try? c.decodeIfPresent(String.self, forKey: .source)
            items = try? c.decodeIfPresent([MealItem].self, forKey: .items)
            totalCalories = try? c.decodeIfPresent(Double.self, forKey: .totalCalories)
            totalProteinG = try? c.decodeIfPresent(Double.self, forKey: .totalProteinG)
            totalCarbsG = try? c.decodeIfPresent(Double.self, forKey: .totalCarbsG)
            totalFatG = try? c.decodeIfPresent(Double.self, forKey: .totalFatG)
            totalFiberG = try? c.decodeIfPresent(Double.self, forKey: .totalFiberG)
            micronutrientTotals = try? c.decodeIfPresent([String: Double?].self, forKey: .micronutrientTotals)
            inflammationScore = try? c.decodeIfPresent(Double.self, forKey: .inflammationScore)
            glycemicScore = try? c.decodeIfPresent(Double.self, forKey: .glycemicScore)
            gutScore = try? c.decodeIfPresent(Double.self, forKey: .gutScore)
            photoUrl = try? c.decodeIfPresent(String.self, forKey: .photoUrl)
            sourceMealLogId = try? c.decodeIfPresent(String.self, forKey: .sourceMealLogId)
            createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
            lastUsedAt = try? c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        }

        var model: FavoriteMeal {
            var scores: MealScores?
            if inflammationScore != nil || glycemicScore != nil || gutScore != nil {
                scores = MealScores(inflammation: Int((inflammationScore ?? 0).rounded()), glycemic: Int((glycemicScore ?? 0).rounded()), digestion: Int((gutScore ?? 0).rounded()))
            }
            return FavoriteMeal(
                id: id, name: name ?? "Meal",
                mealType: mealType.flatMap(MealLog.MealType.init(rawValue:)) ?? .snack,
                source: source.flatMap(MealLog.Source.init(rawValue:)) ?? .photo,
                items: items ?? [], kcal: totalCalories, proteinG: totalProteinG, carbsG: totalCarbsG, fatG: totalFatG, fiberG: totalFiberG,
                micros: micronutrientTotals?.compactMapValues { $0 } ?? [:], scores: scores,
                photoPath: photoUrl.flatMap { MealPhotoRef.storagePath($0) }, sourceMealLogId: sourceMealLogId,
                lastUsedAt: lastUsedAt ?? createdAt ?? Date()
            )
        }
    }

    /// ⚠ Keys must match live `nb_favorite_meals` columns exactly (PGRST204 rejects the whole insert).
    private struct FavoriteBody: Encodable, Sendable {
        let patientId: String
        let name: String
        let mealType: String
        let source: String
        let items: [MealItemBody]
        let totalCalories: Double?
        let totalProteinG: Double?
        let totalCarbsG: Double?
        let totalFatG: Double?
        let totalFiberG: Double?
        let micronutrientTotals: [String: Double]
        let inflammationScore: Int?
        let glycemicScore: Int?
        let gutScore: Int?
        let photoUrl: String?
        let sourceMealLogId: String?
    }

    /// The item shape the edge functions write (`ai_identified_foods[]`), re-emitted as-is.
    struct MealItemBody: Encodable, Sendable {
        let name: String
        let estimatedGrams: Double?
        let kcal: Double?
        let proteinG: Double?
        let carbsG: Double?
        let fatG: Double?
        let fiberG: Double?
        let flags: [String]
        init(_ i: MealItem) {
            name = i.name; estimatedGrams = i.estimatedGrams; kcal = i.kcal; proteinG = i.proteinG; carbsG = i.carbsG; fatG = i.fatG; fiberG = i.fiberG; flags = i.flags
        }
    }

    private struct TouchBody: Encodable, Sendable { let lastUsedAt: String }

    /// `buildRelogRow`: a priced clone logged NOW; `analysis_status` is omitted so the `complete` default applies.
    private struct RelogBody: Encodable, Sendable {
        let patientId: String
        let name: String
        let mealType: String
        let source: String
        let loggedAt: String
        let photoUrl: String?
        let aiIdentifiedFoods: [MealItemBody]
        let totalCalories: Double?
        let totalProteinG: Double?
        let totalCarbsG: Double?
        let totalFatG: Double?
        let totalFiberG: Double?
        let micronutrientTotals: [String: Double]
        let inflammationScore: Int?
        let glycemicScore: Int?
        let gutScore: Int?
    }

    func favorites(patientId: String) async throws -> [FavoriteMeal] {
        let rows: [FavoriteRow] = try await rest.select("nb_favorite_meals", query: [
            PG.select(Self.favoriteColumns), PG.eq("patient_id", patientId), PG.order("last_used_at", descending: true), PG.limit(50),
        ])
        return rows.map(\.model)
    }

    func addFavorite(_ meal: MealLog, patientId: String) async throws -> FavoriteMeal {
        let row: FavoriteRow = try await rest.insert("nb_favorite_meals", body: FavoriteBody(
            patientId: patientId, name: meal.displayName, mealType: (meal.mealType ?? .snack).rawValue, source: "photo",
            items: meal.items.map(MealItemBody.init), totalCalories: meal.totalCalories, totalProteinG: meal.totalProteinG,
            totalCarbsG: meal.totalCarbsG, totalFatG: meal.totalFatG, totalFiberG: meal.totalFiberG, micronutrientTotals: meal.micros,
            inflammationScore: meal.scores?.inflammation, glycemicScore: meal.scores?.glycemic, gutScore: meal.scores?.digestion,
            photoUrl: meal.photoPath, sourceMealLogId: meal.id
        ))
        return row.model
    }

    func removeFavorite(id: String) async throws {
        try await rest.delete("nb_favorite_meals", query: [PG.eq("id", id)])
    }

    func touchFavorite(id: String) async throws {
        try await rest.update("nb_favorite_meals", query: [PG.eq("id", id)], body: TouchBody(lastUsedAt: ISO8601.string(Date())))
    }

    func relogMeal(_ source: RelogSource, patientId: String) async throws -> String {
        let row: IdRow = try await rest.insert("nb_meal_logs", body: RelogBody(
            patientId: patientId, name: source.name, mealType: source.mealType.rawValue, source: source.source.rawValue,
            loggedAt: ISO8601.string(Date()), photoUrl: nil, aiIdentifiedFoods: source.items.map(MealItemBody.init),
            totalCalories: source.kcal, totalProteinG: source.proteinG, totalCarbsG: source.carbsG, totalFatG: source.fatG,
            totalFiberG: source.fiberG, micronutrientTotals: source.micros,
            inflammationScore: source.scores?.inflammation, glycemicScore: source.scores?.glycemic, gutScore: source.scores?.digestion
        ))
        return row.id
    }

    private struct ReactionListRow: Decodable, Sendable { let mealLogId: String; let overall: Double?; let reactionFlags: [String]? }

    func mealReactions(patientId: String, since: Date) async throws -> [String: MealReaction] {
        let rows: [ReactionListRow] = try await rest.select("nb_meal_reactions", query: [
            PG.select("meal_log_id,overall,reaction_flags"), PG.eq("patient_id", patientId), PG.gte("reaction_time", ISO8601.string(since)),
        ])
        var out: [String: MealReaction] = [:]
        for r in rows { out[r.mealLogId] = MealReaction(overall: r.overall, flags: r.reactionFlags ?? []) }
        return out
    }

    // MARK: Profile tab (care_plans · member_entitlements · baseline)

    func carePlan(patientId: String) async throws -> CarePlan? {
        // RLS scopes care_plans to `patient_id = current_member_patient_id()`; the newest active plan wins.
        let plans: [CarePlanRow] = try await rest.select("care_plans", query: [
            PG.select("id,title,start_date,status"), PG.eq("status", "active"),
            PG.order("start_date", descending: true), PG.limit(1),
        ])
        guard let plan = plans.first else { return nil }
        // Curriculum rows pass the RLS gate but are the personalised space's sub-courses, not
        // instructions. `or`, not `neq`: SQL `<>` would also drop rows whose item_kind is null.
        let items: [CarePlanItemRow] = try await rest.select("care_plan_items", query: [
            PG.select("id,domain,title,objective,instruction_text,patient_safe_explanation,status,sort_order"),
            PG.eq("care_plan_id", plan.id),
            PG.or("item_kind.is.null,item_kind.neq.curriculum"),
            PG.order("sort_order"),
        ])
        return CarePlanLogic.assemble(plan: plan, items: items)
    }

    func entitlements(patientId: String) async throws -> [EntitlementRow] {
        try await rest.select("member_entitlements", query: [
            PG.select("access_type,status,starts_at,expires_at"), PG.eq("patient_id", patientId),
        ])
    }

    private struct BaselineBody: Encodable, Sendable {
        let appSex: String
        let appAge: Int
        let appHeightCm: Double
        let appWeightKg: Double
        let activityLevel: String
    }
    private struct BaselineInsertBody: Encodable, Sendable {
        let patientId: String
        let appSex: String
        let appAge: Int
        let appHeightCm: Double
        let appWeightKg: Double
        let activityLevel: String
    }
    private struct PatientIdRow: Decodable, Sendable { let patientId: String }

    /// The Expo `writeProfileRow`: UPDATE first (patient_id only in the WHERE), INSERT when no row was
    /// touched, and a 23505 on that INSERT means the row appeared meanwhile — update again.
    func saveBaseline(patientId: String, values v: BaselineValues) async throws {
        let body = BaselineBody(appSex: v.sex.rawValue, appAge: v.age, appHeightCm: v.heightCm, appWeightKg: v.weightKg, activityLevel: v.activity.rawValue)
        let touched: [PatientIdRow] = try await rest.updateReturning("nb_patient_app_profiles", query: [PG.eq("patient_id", patientId), PG.select("patient_id")], body: body)
        if !touched.isEmpty { return }
        do {
            try await rest.insertRows("nb_patient_app_profiles", body: [BaselineInsertBody(patientId: patientId, appSex: v.sex.rawValue, appAge: v.age, appHeightCm: v.heightCm, appWeightKg: v.weightKg, activityLevel: v.activity.rawValue)])
        } catch {
            // 23505: the row appeared between our UPDATE and our INSERT (patient-register, a second
            // device). It exists now, so the update that just missed it lands; any other failure
            // fails here too and is what the member sees.
            try await rest.update("nb_patient_app_profiles", query: [PG.eq("patient_id", patientId)], body: body)
        }
    }

    private struct NutritionInsertBody: Encodable, Sendable {
        let patientId: String
        let profile: NutritionProfileWrite
        private enum Key: String, CodingKey { case patientId }
        func encode(to encoder: Encoder) throws {
            try profile.encode(to: encoder)
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(patientId, forKey: .patientId)
        }
    }

    /// The targets page's Validate — the same UPDATE-then-INSERT shape as `saveBaseline` (column-scoped grants).
    func saveNutritionProfile(patientId: String, profile: NutritionProfileWrite) async throws {
        let touched: [PatientIdRow] = try await rest.updateReturning("nb_patient_app_profiles", query: [PG.eq("patient_id", patientId), PG.select("patient_id")], body: profile)
        if !touched.isEmpty { return }
        do {
            try await rest.insertRows("nb_patient_app_profiles", body: [NutritionInsertBody(patientId: patientId, profile: profile)])
        } catch {
            try await rest.update("nb_patient_app_profiles", query: [PG.eq("patient_id", patientId)], body: profile)
        }
    }

    // MARK: Messaging (patient_messages)

    private struct ClinicRow: Decodable, Sendable { let id: String; let clinicId: String? }

    func memberClinicId(userId: String) async throws -> String? {
        let row: ClinicRow? = try await rest.selectOne("patients", query: [PG.select("id,clinic_id"), PG.eq("auth_user_id", userId)])
        return row?.clinicId
    }

    /// The PATIENT-readable columns, listed explicitly — never `*` (the same row carries the clinician's
    /// unsent `ai_draft_*` columns, and RLS here is row-scoped, not column-scoped).
    private static let messageColumns = "id,sender_type,body,created_at,read_by_patient_at,visibility_class,context_kind,context_meal_id,context_day"

    func messages() async throws -> [PatientMessage] {
        let rows: [PatientMessageRow] = try await rest.select("patient_messages", query: [
            PG.select(Self.messageColumns),
            PG.inList("visibility_class", ["patient_visible", "patient_visible_after_approval"]),
            PG.order("created_at"), PG.limit(200),
        ])
        return rows.map(\.message)
    }

    private struct MessageBody: Encodable, Sendable {
        let patientId: String
        let clinicId: String
        let senderType: String
        let senderUserId: String?
        let body: String
        let visibilityClass: String
        let contextKind: String?
        let contextMealId: String?
        let contextDay: String?
    }
    private struct MessageIdRow: Decodable, Sendable { let id: String }

    func sendMessage(patientId: String, clinicId: String, body: String, context: MessageContext?) async throws -> String {
        let cols: (kind: String?, mealId: String?, day: String?) = context?.columns ?? (kind: nil, mealId: nil, day: nil)
        let row: MessageIdRow = try await rest.insert("patient_messages", body: MessageBody(
            patientId: patientId, clinicId: clinicId, senderType: "patient", senderUserId: nil,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines), visibilityClass: "patient_visible",
            contextKind: cols.kind, contextMealId: cols.mealId, contextDay: cols.day
        ))
        return row.id
    }

    private struct NotifyBody: Encodable, Sendable { let messageId: String }

    func notifyMessage(id: String) async throws {
        _ = try await functions.invokeRaw("message-notify", body: NotifyBody(messageId: id))
    }

    func markMessagesRead() async throws {
        let _: Int = try await rest.rpc("member_mark_messages_read", body: EmptyBody())
    }

    // MARK: Account

    private struct FeedbackBody: Encodable, Sendable { let message: String; let appVersion: String }
    private struct OkResult: Decodable, Sendable { let ok: Bool? }

    func sendFeedback(message: String, appVersion: String) async throws {
        let result: OkResult = try await functions.invoke("member-feedback", body: FeedbackBody(message: message, appVersion: appVersion), snakeCase: false)
        guard result.ok == true else { throw AppError.server(status: 500) }
    }

    private struct DeletedResult: Decodable, Sendable { let deleted: Bool?; let error: String? }

    func deleteAccount() async throws {
        let result: DeletedResult = try await functions.invoke("delete-account", body: EmptyBody())
        guard result.deleted == true else { throw AppError.validation(message: result.error ?? "Deletion did not complete.") }
    }

    private struct ConsentsBody: Encodable, Sendable { let pLocale: String; let pIncludeDrafts: Bool }

    func consents(locale: String) async throws -> [ConsentItem] {
        try await rest.rpc("member_pending_consents", body: ConsentsBody(pLocale: locale, pIncludeDrafts: false))
    }

    private struct DecisionBody: Encodable, Sendable { let key: String; let version: String; let granted: Bool; let defaultState: Bool }
    private struct RecordBatchBody: Encodable, Sendable {
        let pDecisions: [DecisionBody]
        let pLocale: String
        let pUserAgent: String
        let pAppVersion: String
        let pUiTemplateVersion: String
        let pPrivacyNoticeVersion: String
        let pPresentedKeys: [String]
        let pChannel: String
    }

    func recordConsents(_ decisions: [ConsentDecision], presentedKeys: [String], privacyNoticeVersion: String, locale: String) async throws {
        let body = RecordBatchBody(
            pDecisions: decisions.map { DecisionBody(key: $0.key, version: $0.version, granted: $0.granted, defaultState: $0.defaultState) },
            pLocale: locale,
            pUserAgent: "FunctionAlps/\(AppInfo.version) (ios)",
            pAppVersion: AppInfo.version,
            pUiTemplateVersion: ConsentLogic.uiTemplateVersion,
            pPrivacyNoticeVersion: privacyNoticeVersion,
            pPresentedKeys: presentedKeys,
            pChannel: "app_privacy"
        )
        let _: [String] = try await rest.rpc("record_consent_batch", body: body)
    }

    private struct RevokeBody: Encodable, Sendable { let pConsentKey: String; let pChannel: String }

    func revokeConsent(key: String) async throws {
        let _: Int = try await rest.rpc("revoke_consent", body: RevokeBody(pConsentKey: key, pChannel: "app_privacy"))
    }

    func legalDocuments(keys: [String], locale: String) async throws -> [LegalDocument] {
        try await rest.select("consent_definitions", query: [
            PG.select("consent_key,version,locale,title,summary,body_md,display_order"),
            PG.inList("consent_key", keys), PG.eq("locale", locale), PG.eq("review_status", "approved"),
            PG.isNull("superseded_at"), PG.order("display_order"),
        ])
    }

    func dataCount(table: String, patientId: String) async throws -> Int {
        try await rest.count(table, query: [PG.eq("patient_id", patientId)])
    }

    func dataRows(table: String, patientId: String) async throws -> Data {
        try await rest.selectRaw(table, query: [PG.select("*"), PG.eq("patient_id", patientId)])
    }

    // MARK: Wearables (wearable-ingest · wearable_daily_labeled · wearable_connections)

    func ingestWearable(_ batch: WearableBatch) async throws -> WearableIngestResult {
        try await functions.invoke("wearable-ingest", body: batch)
    }

    func wearableDaily(patientId: String, since: String) async throws -> [WearableLabeledRow] {
        try await rest.select("wearable_daily_labeled", query: [
            PG.select("day,metric,value,data_source_id,layer"), PG.eq("patient_id", patientId),
            PG.inList("layer", ["raw", "analytics"]), PG.gte("day", since), PG.order("day"),
        ])
    }

    func wearableConnections(patientId: String) async throws -> [WearableConnectionRow] {
        try await rest.select("wearable_connections", query: [
            PG.select("data_source_id,data_source_name,status,connected_at"), PG.eq("patient_id", patientId),
            PG.order("connected_at", descending: true),
        ])
    }
}
