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
        guard let row else { return nil }
        // Legacy 1–10 → 0–100 only when v2 is absent; stress legacy is "stress", v2 is calmness.
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
