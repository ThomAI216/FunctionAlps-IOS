import Foundation

/// The one place that knows CM OS table, column, RPC and edge-function names.
/// Every query is the member's OWN rows under RLS (patient_id = their patients.id).
/// Column lists mirror the Expo app's selects (docs/audit/app-auth-data.md §3).
struct SupabaseBackend: FunctionAlpsBackend {
    private let rest: PostgRESTClient
    private let functions: EdgeFunctionClient

    init(rest: PostgRESTClient, functions: EdgeFunctionClient) {
        self.rest = rest
        self.functions = functions
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

    private struct MealRow: Decodable, Sendable {
        let id: String
        let loggedAt: Date
        let mealType: String?
        let name: String?
        let source: String?
        let analysisStatus: String?
        let totalCalories: Double?
        let totalProteinG: Double?
        let totalCarbsG: Double?
        let totalFatG: Double?
        let photoUrl: String?
    }

    func meals(patientId: String, since: Date) async throws -> [MealLog] {
        let rows: [MealRow] = try await rest.select("nb_meal_logs", query: [
            PG.select("id,logged_at,meal_type,name,source,analysis_status,total_calories,total_protein_g,total_carbs_g,total_fat_g,photo_url"),
            PG.eq("patient_id", patientId),
            PG.gte("logged_at", ISO8601.string(since)),
            PG.order("logged_at", descending: true),
            PG.limit(100),
        ])
        return rows.map {
            MealLog(
                id: $0.id,
                loggedAt: $0.loggedAt,
                mealType: $0.mealType.flatMap(MealLog.MealType.init(rawValue:)),
                name: $0.name,
                source: $0.source.flatMap(MealLog.Source.init(rawValue:)),
                analysisStatus: $0.analysisStatus.flatMap(MealLog.AnalysisStatus.init(rawValue:)),
                totalCalories: $0.totalCalories,
                totalProteinG: $0.totalProteinG,
                totalCarbsG: $0.totalCarbsG,
                totalFatG: $0.totalFatG,
                photoPath: $0.photoUrl
            )
        }
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
