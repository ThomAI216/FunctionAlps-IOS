import Foundation

/// What the Home screen needs for one calendar day. Server-computed values only;
/// the app sums and formats, it does not score (PRD §41, see IOS_MIGRATION_MAP §scores).
struct TodaySnapshot: Sendable, Equatable {
    let day: String              // YYYY-MM-DD in the member's local calendar
    let meals: [MealLog]
    let checkin: DailyCheckin?
    let unreadClinicianMessages: Int

    var totalCalories: Double { meals.compactMap(\.totalCalories).reduce(0, +) }
    var totalProteinG: Double { meals.compactMap(\.totalProteinG).reduce(0, +) }
    var totalCarbsG: Double { meals.compactMap(\.totalCarbsG).reduce(0, +) }
    var totalFatG: Double { meals.compactMap(\.totalFatG).reduce(0, +) }
}

struct MealLog: Identifiable, Sendable, Equatable {
    enum MealType: String, Sendable { case breakfast, lunch, dinner, snack, other }
    enum Source: String, Sendable { case photo, text, voice }
    enum AnalysisStatus: String, Sendable { case queued, pending, analyzing, complete, failed }

    let id: String
    let loggedAt: Date
    let mealType: MealType?
    let name: String?
    let source: Source?
    let analysisStatus: AnalysisStatus?
    let totalCalories: Double?
    let totalProteinG: Double?
    let totalCarbsG: Double?
    let totalFatG: Double?
    /// Storage PATH in the private `meal-images` bucket (signed URL needed to display).
    let photoPath: String?

    var isAnalysed: Bool { analysisStatus == .complete || (analysisStatus == nil && totalCalories != nil) }
}

/// One `patient_daily_checkins` row. Markers are 0–100, higher = better;
/// `calmness` is the column named `stress_score` (it stores calmness — never invert).
struct DailyCheckin: Sendable, Equatable {
    let day: String
    let functionalCompletedAt: Date?
    let gutCompletedAt: Date?
    let energy: Int?
    let mood: Int?
    let sleep: Int?
    let calmness: Int?
    let gutOverall: Int?

    var isFunctionalDone: Bool { functionalCompletedAt != nil }
    var isGutDone: Bool { gutCompletedAt != nil }
}
