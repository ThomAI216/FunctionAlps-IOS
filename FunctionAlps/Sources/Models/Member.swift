import Foundation

/// The signed-in member as the app understands them. Identity comes from the
/// auth session (never the PII vault); the profile comes from the app profile row.
struct Member: Sendable, Equatable {
    let userId: String
    let patientId: String
    let email: String?
    let displayName: String
    let profile: MemberProfile?

    /// The FunctionAlps app deliberately says "client", never "patient" (audit D-18).
    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
}

/// Subset of `nb_patient_app_profiles` the member-facing app shows (all nullable).
struct MemberProfile: Sendable, Equatable {
    enum Sex: String, Sendable { case male, female, other }
    enum GoalMode: String, Sendable { case build, cut, maintain }

    let sex: Sex?
    let age: Int?
    let heightCm: Double?
    let weightKg: Double?
    let activityLevel: String?
    let healthGoals: [String]
    let currentComplaints: [String]
    let dietaryPattern: String?
    let targetCalories: Int?
    let targetProteinG: Int?
    let targetCarbsG: Int?
    let targetFatG: Int?
    let goalMode: GoalMode?
    let onboardingCompletedAt: Date?
    let locale: String?
    /// The DB trigger's daily energy estimate (`tdee_kcal`), the compass number.
    var tdeeKcal: Double? = nil
    // The targets page (nutrition-macros): inputs the member may tune there.
    var estimatedBodyFatPercent: Double? = nil
    var customCalorieOffsetKcal: Int? = nil
    var mealsPerDay: Int? = nil
    var snacksPerDay: Int? = nil
    var macrosCustomized: Bool = false

    /// The Expo `profileComplete`: what the macro pages need before they can show targets.
    var hasBodyData: Bool { weightKg != nil && heightCm != nil && age != nil }
    var hasTargets: Bool { targetCalories != nil && targetProteinG != nil && targetCarbsG != nil && targetFatG != nil }
}
