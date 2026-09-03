import Foundation

/// What the Home screen needs for one calendar day. Server-computed values only;
/// the app sums and formats, it does not score (PRD §41, see IOS_MIGRATION_MAP §scores).
struct TodaySnapshot: Sendable, Equatable {
    let day: String              // YYYY-MM-DD in the member's local calendar
    let meals: [MealLog]
    let checkin: DailyCheckin?
    let unreadClinicianMessages: Int
    /// Today's saved check-in moments (morning / midday / evening), oldest first.
    var moments: [CheckinMoment] = []

    var totalCalories: Double { meals.compactMap(\.totalCalories).reduce(0, +) }
    var totalProteinG: Double { meals.compactMap(\.totalProteinG).reduce(0, +) }
    var totalCarbsG: Double { meals.compactMap(\.totalCarbsG).reduce(0, +) }
    var totalFatG: Double { meals.compactMap(\.totalFatG).reduce(0, +) }
}

/// One `nb_meal_logs` row as the member-facing app understands it.
struct MealLog: Identifiable, Sendable, Equatable {
    enum MealType: String, Sendable, CaseIterable { case breakfast, lunch, dinner, snack, other }
    enum Source: String, Sendable { case photo, text, voice }

    /// Mirrors the live `nb_meal_logs_analysis_status_check` constraint:
    /// queued → identifying → pricing → complete | needs_input | failed.
    /// The column DEFAULT is `complete`, so an absent/unknown value means "old row, nothing owed".
    enum AnalysisStatus: String, Sendable {
        case queued, identifying, pricing, complete, failed
        case needsInput = "needs_input"

        /// Nothing further happens automatically from these states — a watcher stops here.
        var isTerminal: Bool { self == .complete || self == .needsInput || self == .failed }
        var isWorking: Bool { !isTerminal }
    }

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
    /// Storage PATHS in the private `meal-images` bucket, ordered (signed URL needed to display).
    let photoPaths: [String]
    let analysisError: String?
    let totalFiberG: Double?
    /// Per-ingredient breakdown (`ai_identified_foods`) — the model's, never the member's words.
    let items: [MealItem]
    /// Present only when all three food scores exist; never synthesised from zeros.
    let scores: MealScores?
    /// The member's OWN words (`patient_note`). Never merged with model text.
    let patientNote: String?

    init(
        id: String,
        loggedAt: Date,
        mealType: MealType? = nil,
        name: String? = nil,
        source: Source? = nil,
        analysisStatus: AnalysisStatus? = nil,
        totalCalories: Double? = nil,
        totalProteinG: Double? = nil,
        totalCarbsG: Double? = nil,
        totalFatG: Double? = nil,
        photoPath: String? = nil,
        photoPaths: [String]? = nil,
        analysisError: String? = nil,
        totalFiberG: Double? = nil,
        items: [MealItem] = [],
        scores: MealScores? = nil,
        patientNote: String? = nil
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.mealType = mealType
        self.name = name
        self.source = source
        self.analysisStatus = analysisStatus
        self.totalCalories = totalCalories
        self.totalProteinG = totalProteinG
        self.totalCarbsG = totalCarbsG
        self.totalFatG = totalFatG
        self.photoPaths = photoPaths ?? photoPath.map { [$0] } ?? []
        self.analysisError = analysisError
        self.totalFiberG = totalFiberG
        self.items = items
        self.scores = scores
        self.patientNote = patientNote
    }

    var photoPath: String? { photoPaths.first }
    var status: AnalysisStatus { analysisStatus ?? .complete }
    var isAnalysed: Bool { status == .complete }
    /// The model's dish name, else the slot, else a neutral word.
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        return mealType?.localizedName ?? String(localized: "meal.type.other", defaultValue: "Meal")
    }
}

/// One identified food on a meal (`ai_identified_foods[]`). Numbers are estimates.
struct MealItem: Sendable, Equatable, Decodable {
    let name: String
    let estimatedGrams: Double?
    let kcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let flags: [String]

    init(name: String, estimatedGrams: Double? = nil, kcal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil, fiberG: Double? = nil, flags: [String] = []) {
        self.name = name
        self.estimatedGrams = estimatedGrams
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.flags = flags
    }

    private enum CodingKeys: String, CodingKey { case name, estimatedGrams, kcal, proteinG, carbsG, fatG, fiberG, flags }

    /// Lenient on purpose: model output occasionally carries numbers as strings or omits fields,
    /// and one odd item must not blank the whole meal.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? String(localized: "meal.item.unknown", defaultValue: "Food")
        estimatedGrams = Self.number(c, .estimatedGrams)
        kcal = Self.number(c, .kcal)
        proteinG = Self.number(c, .proteinG)
        carbsG = Self.number(c, .carbsG)
        fatG = Self.number(c, .fatG)
        fiberG = Self.number(c, .fiberG)
        flags = (try? c.decodeIfPresent([String].self, forKey: .flags)) ?? []
    }

    private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

/// Per-meal food scores, 0–100, higher = better. They describe the FOOD, not the person.
struct MealScores: Sendable, Equatable {
    let inflammation: Int
    let glycemic: Int
    let digestion: Int
}

/// `nb_meal_logs.photo_url` holds a storage PATH on new rows but a full public URL on
/// legacy rows (bucket was public before 2026-07-07). Both must keep resolving.
enum MealPhotoRef {
    static let bucket = "meal-images"

    static func storagePath(_ ref: String?) -> String? {
        guard let ref else { return nil }
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let marker = "/\(bucket)/"
        if let range = trimmed.range(of: marker) {
            let rest = trimmed[range.upperBound...]
            let path = rest.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
            return path.isEmpty ? nil : path
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") { return nil }
        let path = trimmed.drop { $0 == "/" }
        return path.isEmpty ? nil : String(path)
    }

    /// Same rule as the edge functions' `photoPathsFor`: `photo_urls` is the whole ordered set
    /// when present (it INCLUDES element 0); otherwise `photo_url` alone. Never concatenate the two.
    static func paths(photoUrl: String?, photoUrls: [String]?) -> [String] {
        let many = (photoUrls ?? []).compactMap { storagePath($0) }
        if !many.isEmpty { return Array(many.prefix(4)) }
        return storagePath(photoUrl).map { [$0] } ?? []
    }
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
