import Foundation

/// "Your data": what CM OS holds about the member, counted table by table under their own RLS
/// (the Expo `lib/account/user-data.ts` bundle, summarised).
struct DataSummary: Sendable, Equatable {
    struct Count: Sendable, Equatable, Identifiable {
        let key: String
        let label: String
        let value: Int
        var id: String { key }
    }
    struct RecentMeal: Sendable, Equatable, Identifiable {
        let id: String
        let name: String
        let loggedAt: Date?
    }

    let profileName: String?
    let age: Int?
    let sex: String?
    let goals: [String]
    let dietaryPattern: String?
    let counts: [Count]
    let recentMeals: [RecentMeal]
}

/// The tables the export walks, in the Expo order — every one keyed on `patient_id`.
enum ExportTables {
    static let ordered: [(key: String, table: String)] = [
        ("profile", "nb_patient_app_profiles"),
        ("meals", "nb_meal_logs"),
        ("mealReactions", "nb_meal_reactions"),
        ("checkins", "patient_daily_checkins"),
        ("checkinEvents", "nb_checkin_events"),
        ("assessments", "nb_assessment_responses"),
        ("reports", "nb_reports"),
        ("consents", "nb_app_consents"),
        ("patterns", "nb_user_patterns"),
        ("reportContent", "nb_report_content"),
    ]
}

// MARK: - Baseline (age · sex · height · weight · activity)

/// The five values `nb_patient_app_profiles.activity_level` accepts (a CHECK constraint the DB
/// trigger reads to compute `tdee_kcal`). The member sees the PRD copy; the row stores the key.
enum ActivityLevel: String, CaseIterable, Sendable, Identifiable {
    case sedentary, lightlyActive = "lightly_active", moderatelyActive = "moderately_active", veryActive = "very_active", extremelyActive = "extremely_active"
    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .lightlyActive: 1.35
        case .moderatelyActive: 1.55
        case .veryActive: 1.7
        case .extremelyActive: 1.9
        }
    }

    var title: String {
        switch self {
        case .sedentary: String(localized: "activity.sedentary.title", defaultValue: "Mostly sedentary")
        case .lightlyActive: String(localized: "activity.lightly.title", defaultValue: "Lightly active")
        case .moderatelyActive: String(localized: "activity.moderately.title", defaultValue: "Moderately active")
        case .veryActive: String(localized: "activity.very.title", defaultValue: "Very active")
        case .extremelyActive: String(localized: "activity.extremely.title", defaultValue: "Highly active")
        }
    }

    var body: String {
        switch self {
        case .sedentary: String(localized: "activity.sedentary.body", defaultValue: "Most of my day is seated, with little structured exercise.")
        case .lightlyActive: String(localized: "activity.lightly.body", defaultValue: "I walk regularly or exercise around 1–2 times per week.")
        case .moderatelyActive: String(localized: "activity.moderately.body", defaultValue: "I exercise around 3–4 times per week and/or have a reasonably active lifestyle.")
        case .veryActive: String(localized: "activity.very.body", defaultValue: "I train most days or have a physically demanding lifestyle.")
        case .extremelyActive: String(localized: "activity.extremely.body", defaultValue: "I train intensely, sometimes more than once per day, or have a very physically demanding lifestyle.")
        }
    }
}

/// A complete, valid baseline — what one profile write carries (the Expo `BaselineValues`).
struct BaselineValues: Sendable, Equatable {
    let sex: MemberProfile.Sex
    let age: Int
    let heightCm: Double
    let weightKg: Double
    let activity: ActivityLevel
}

/// The baseline form's pure core: ranges, validation, and the same energy estimate the DB trigger
/// makes (Harris-Benedict × the NEAT factor), so the number never jumps between screens.
enum BaselineLogic {
    static let ageRange = 16...100
    static let heightRange = 120.0...230.0
    static let weightRange = 30.0...300.0

    /// Accepts "72", "72,5", "72.5".
    static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    static func ageError(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard let v = number(text), v == v.rounded(), ageRange.contains(Int(v)) else {
            return String(localized: "baseline.age.invalid", defaultValue: "Enter an age between 16 and 100.")
        }
        return nil
    }

    static func heightError(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard let v = number(text), heightRange.contains(v) else {
            return String(localized: "baseline.height.invalid", defaultValue: "Enter a height between 120 and 230 cm.")
        }
        return nil
    }

    static func weightError(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard let v = number(text), weightRange.contains(v) else {
            return String(localized: "baseline.weight.invalid", defaultValue: "Enter a weight between 30 and 300 kg.")
        }
        return nil
    }

    static func resolve(sex: MemberProfile.Sex?, age: String, height: String, weight: String, activity: ActivityLevel?) -> BaselineValues? {
        guard let sex, let activity,
              ageError(age) == nil, heightError(height) == nil, weightError(weight) == nil,
              let a = number(age), let h = number(height), let w = number(weight),
              !age.isEmpty, !height.isEmpty, !weight.isEmpty else { return nil }
        return BaselineValues(sex: sex, age: Int(a), heightCm: h, weightKg: w, activity: activity)
    }

    /// Harris-Benedict BMR (the CM OS `compute_macro_targets()` formula when body fat is unknown).
    static func bmr(_ v: BaselineValues) -> Double {
        switch v.sex {
        case .male: 88.362 + 13.397 * v.weightKg + 4.799 * v.heightCm - 5.677 * Double(v.age)
        default: 447.593 + 9.247 * v.weightKg + 3.098 * v.heightCm - 4.330 * Double(v.age)
        }
    }

    /// The local estimate, rounded to the nearest 50 like the compass screen.
    static func estimateKcal(_ v: BaselineValues) -> Int {
        Int((bmr(v) * v.activity.multiplier / 50).rounded() * 50)
    }

    static func roundToNearest50(_ kcal: Double) -> Int { Int((kcal / 50).rounded() * 50) }
}
