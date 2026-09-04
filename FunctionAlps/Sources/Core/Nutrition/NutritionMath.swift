import Foundation

/// The Expo `lib/utils/tdee.ts`, `macro-context-text.ts`, `meal-repartition.ts` and
/// `nutrition/macros-view.ts`, line for line: what the targets page previews while the member drags,
/// and what the macros pages read. The DB trigger on `nb_patient_app_profiles` owns the stored
/// targets; these numbers are the instant preview and must stay byte-identical to that trigger.
enum NutritionMath {
    typealias Goal = MemberProfile.GoalMode

    struct MacroTargets: Sendable, Equatable {
        var proteinG: Int
        var carbsG: Int
        var fatG: Int
        var calories: Int
    }

    // MARK: Energy

    static func harrisBenedictBMR(weightKg: Double, heightCm: Double, age: Int, sex: MemberProfile.Sex) -> Double {
        if sex == .male { return 88.362 + 13.397 * weightKg + 4.799 * heightCm - 5.677 * Double(age) }
        return 447.593 + 9.247 * weightKg + 3.098 * heightCm - 4.33 * Double(age)
    }

    static func katchMcArdleBMR(weightKg: Double, bodyFatPercent: Double) -> Double {
        let lbm = weightKg * (1 - bodyFatPercent / 100)
        return 370 + 21.6 * lbm
    }

    /// A real body-fat ⇒ Katch-McArdle, absent ⇒ Harris-Benedict (never a fabricated 18 %).
    static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: MemberProfile.Sex, bodyFatPercent: Double?) -> Double {
        if let bf = bodyFatPercent, bf > 0 { return katchMcArdleBMR(weightKg: weightKg, bodyFatPercent: bf) }
        return harrisBenedictBMR(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex)
    }

    static func tdee(weightKg: Double, heightCm: Double, age: Int, sex: MemberProfile.Sex, activity: ActivityLevel?, bodyFatPercent: Double?) -> Int {
        let factor = activity?.multiplier ?? 1.55
        return Int((bmr(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex, bodyFatPercent: bodyFatPercent) * factor).rounded())
    }

    /// Body-fat-scaled calorie offset: larger deficits when there is more fat to lose, larger surpluses when lean.
    static func goalOffset(goal: Goal, bodyFatPercent: Double) -> Int {
        switch goal {
        case .maintain: return 0
        case .cut:
            if bodyFatPercent < 18 { return -300 }
            if bodyFatPercent <= 25 { return -400 }
            return -500
        case .build:
            if bodyFatPercent > 25 { return 150 }
            if bodyFatPercent >= 18 { return 250 }
            return 300
        }
    }

    /// Women 1.5 g/kg, men 1.8 g/kg protein; fat 40 % of goal calories; carbs the remainder (floor 0).
    static func goalMacros(tdee: Int, weightKg: Double, sex: MemberProfile.Sex, goal: Goal, bodyFatPercent: Double?) -> MacroTargets {
        let bf = bodyFatPercent ?? 22
        let goalCalories = Double(tdee + goalOffset(goal: goal, bodyFatPercent: bf))
        let proteinPerKg = sex == .female ? 1.5 : 1.8
        let proteinG = Int((weightKg * proteinPerKg).rounded())
        let proteinKcal = Double(proteinG * 4)
        let fatKcal = goalCalories * 0.4
        let fatG = Int((fatKcal / 9).rounded())
        let carbsKcal = goalCalories - proteinKcal - fatKcal
        let carbsG = max(0, Int((carbsKcal / 4).rounded()))
        return MacroTargets(proteinG: proteinG, carbsG: carbsG, fatG: fatG, calories: Int(goalCalories.rounded()))
    }

    /// The Expo `getGoalFromHealthGoals`: muscle → build, weight/fat → cut, else maintain.
    static func goal(fromHealthGoals goals: [String]) -> Goal {
        if goals.contains(where: { $0.contains("muscle") }) { return .build }
        if goals.contains(where: { $0.contains("weight") || $0.contains("fat") }) { return .cut }
        return .maintain
    }

    /// Fibre target: 14 g per 1000 kcal, never under 25 g.
    static func fiberTarget(calories: Int) -> Int { max(25, Int((Double(calories) / 1000 * 14).rounded())) }

    // MARK: Slider context copy

    static func proteinContext(gPerKg: Double) -> String {
        if gPerKg < 1.5 { return String(localized: "targets.ctx.protein.low", defaultValue: "Too low · minimum for basic maintenance only. Not enough to support activity.") }
        if gPerKg <= 1.8 { return String(localized: "targets.ctx.protein.good", defaultValue: "Good · solid range for most active adults. Supports recovery and lean mass.") }
        if gPerKg <= 2.1 { return String(localized: "targets.ctx.protein.great", defaultValue: "Great · optimal for performance and lean muscle. Ideal for most training goals.") }
        return String(localized: "targets.ctx.protein.high", defaultValue: "High · for aggressive build or cutting phases. Monitor kidney health if sustained.")
    }

    static func fatContext(percent: Int) -> String {
        if percent <= 25 { return String(localized: "targets.ctx.fat.veryLow", defaultValue: "Very low fat. Risk of hormone disruption if sustained long-term.") }
        if percent < 35 { return String(localized: "targets.ctx.fat.moderate", defaultValue: "Moderate fat. Works well for higher carb approaches.") }
        if percent <= 40 { return String(localized: "targets.ctx.fat.optimal", defaultValue: "Optimal range for hormone health, vitamin absorption, and satiety.") }
        return String(localized: "targets.ctx.fat.high", defaultValue: "High fat / low carb approach. Suits keto or insulin resistance protocols.")
    }

    static func carbsContext(carbsG: Int, goalCalories: Int) -> String {
        let pct = goalCalories > 0 ? Int((Double(carbsG * 4) / Double(goalCalories) * 100).rounded()) : 0
        if carbsG <= 50 { return String(localized: "targets.ctx.carbs.keto", defaultValue: "Very low carbs · ketogenic range. May impair high-intensity exercise.") }
        if pct < 25 { return String(localized: "targets.ctx.carbs.low", defaultValue: "Low carbs. Fine for sedentary days, but may limit training performance.") }
        if pct <= 45 { return String(localized: "targets.ctx.carbs.moderate", defaultValue: "Moderate carbs. Balanced approach for most active adults.") }
        return String(localized: "targets.ctx.carbs.high", defaultValue: "Higher carbs. Great for endurance training and glycogen replenishment.")
    }

    struct OffsetWarning: Sendable, Equatable {
        enum Tone: Sendable { case good, ok, caution }
        let message: String
        let tone: Tone
    }

    static func offsetWarning(offset: Int, goal: Goal, bodyFatPercent: Double) -> OffsetWarning? {
        switch goal {
        case .maintain: return nil
        case .cut:
            let aggressive = bodyFatPercent > 25 ? -600 : -500
            if offset >= -300 { return OffsetWarning(message: String(localized: "targets.warn.cut.mild", defaultValue: "Mild deficit · sustainable, minimal muscle risk."), tone: .good) }
            if offset >= aggressive { return OffsetWarning(message: String(localized: "targets.warn.cut.moderate", defaultValue: "Moderate deficit · effective for most people."), tone: .ok) }
            return OffsetWarning(message: String(localized: "targets.warn.cut.aggressive", defaultValue: "⚠️ Aggressive deficit. Risk of muscle loss. Don’t go beyond this without talking to your nutritionist."), tone: .caution)
        case .build:
            if offset <= 300 { return OffsetWarning(message: String(localized: "targets.warn.build.lean", defaultValue: "Lean bulk · minimal fat gain, steady muscle progress."), tone: .good) }
            if offset <= 500 { return OffsetWarning(message: String(localized: "targets.warn.build.standard", defaultValue: "Standard bulk · good for muscle building."), tone: .ok) }
            return OffsetWarning(message: String(localized: "targets.warn.build.aggressive", defaultValue: "⚠️ Aggressive surplus. Higher fat gain likely. Consult your nutritionist before going this high."), tone: .caution)
        }
    }

    // MARK: Meals & snacks repartition

    enum SlotKind: Sendable, Equatable {
        case mainMeal, breakfast, lunch, dinner, meal(Int)
        case snack, morningSnack, eveningSnack, snackN(Int)

        var isSnack: Bool {
            switch self { case .snack, .morningSnack, .eveningSnack, .snackN: true; default: false }
        }

        var title: String {
            switch self {
            case .mainMeal: String(localized: "slot.mainMeal", defaultValue: "Main meal")
            case .breakfast: String(localized: "slot.breakfast", defaultValue: "Breakfast")
            case .lunch: String(localized: "slot.lunch", defaultValue: "Lunch")
            case .dinner: String(localized: "slot.dinner", defaultValue: "Dinner")
            case .meal(let n): String(localized: "slot.mealN", defaultValue: "Meal \(n)")
            case .snack: String(localized: "slot.snack", defaultValue: "Snack")
            case .morningSnack: String(localized: "slot.morningSnack", defaultValue: "Morning snack")
            case .eveningSnack: String(localized: "slot.eveningSnack", defaultValue: "Evening snack")
            case .snackN(let n): String(localized: "slot.snackN", defaultValue: "Snack \(n)")
            }
        }

        var guidance: String {
            switch self {
            case .breakfast: String(localized: "slot.guide.breakfast", defaultValue: "Very low carbs, protein-first to stabilize appetite and energy.")
            case .morningSnack: String(localized: "slot.guide.morningSnack", defaultValue: "Main carb window to fuel the middle of your day.")
            case .lunch: String(localized: "slot.guide.lunch", defaultValue: "Highest carb meal with lean protein for performance and recovery.")
            case .eveningSnack: String(localized: "slot.guide.eveningSnack", defaultValue: "Second carb-focused window, portion-controlled.")
            case .dinner: String(localized: "slot.guide.dinner", defaultValue: "Lower-carb dinner with protein and fiber-forward choices.")
            case .snack, .snackN: String(localized: "slot.guide.snack", defaultValue: "Small structured snack: mostly protein with controlled carbs.")
            case .mainMeal, .meal: String(localized: "slot.guide.default", defaultValue: "Balanced protein, carbs, and fats around your activity.")
            }
        }
    }

    struct RepartitionSlot: Identifiable, Sendable, Equatable {
        let kind: SlotKind
        let protein: Int
        let carbs: Int
        let fat: Int
        var id: String { kind.title }
        var title: String { kind.title }
        var guidance: String { kind.guidance }
    }

    static func mealSlots(_ count: Int) -> [SlotKind] {
        if count <= 1 { return [.mainMeal] }
        if count == 2 { return [.lunch, .dinner] }
        if count == 3 { return [.breakfast, .lunch, .dinner] }
        var slots: [SlotKind] = [.breakfast, .lunch]
        for i in 0..<(count - 3) { slots.append(.meal(i + 3)) }
        slots.append(.dinner)
        return slots
    }

    static func snackSlots(_ count: Int) -> [SlotKind] {
        if count <= 0 { return [] }
        if count == 1 { return [.snack] }
        if count == 2 { return [.morningSnack, .eveningSnack] }
        var slots: [SlotKind] = [.morningSnack, .eveningSnack]
        for i in 0..<(count - 2) { slots.append(.snackN(i + 3)) }
        return slots
    }

    /// Largest-remainder split of `total` along `ratios` (the Expo `distributeByRatio`).
    static func distribute(_ total: Int, ratios: [Double]) -> [Int] {
        guard !ratios.isEmpty else { return [] }
        let sum = ratios.reduce(0, +)
        if sum <= 0 {
            let even = total / ratios.count
            var result = Array(repeating: even, count: ratios.count)
            var remainder = total - even * ratios.count
            var i = 0
            while remainder > 0, i < result.count { result[i] += 1; remainder -= 1; i += 1 }
            return result
        }
        let raw = ratios.map { $0 / sum * Double(total) }
        var base = raw.map { Int($0.rounded(.down)) }
        var remainder = total - base.reduce(0, +)
        let ranking = raw.enumerated().map { (index: $0.offset, fraction: $0.element - $0.element.rounded(.down)) }
            .sorted { $0.fraction > $1.fraction }
        var r = 0
        while remainder > 0, r < ranking.count { base[ranking[r].index] += 1; remainder -= 1; r += 1 }
        return base
    }

    static func repartitionPlan(meals: Int, snacks: Int, targets: MacroTargets) -> [RepartitionSlot] {
        let slots = mealSlots(max(1, meals)) + snackSlots(max(0, snacks))
        let carbRatios: [Double] = slots.map { s in
            switch s {
            case .breakfast: 0.05
            case .morningSnack: 0.24
            case .lunch: 0.36
            case .eveningSnack: 0.2
            case .dinner: 0.1
            default: s.isSnack ? 0.08 : 0.12
            }
        }
        let proteinRatios: [Double] = slots.map { s in
            if s.isSnack { return 0.08 }
            switch s { case .breakfast: return 0.24; case .lunch: return 0.34; case .dinner: return 0.32; default: return 0.2 }
        }
        let fatRatios: [Double] = slots.map { s in
            if s.isSnack { return 0.06 }
            switch s { case .breakfast: return 0.24; case .lunch: return 0.32; case .dinner: return 0.3; default: return 0.22 }
        }
        let proteins = distribute(targets.proteinG, ratios: proteinRatios)
        let carbs = distribute(targets.carbsG, ratios: carbRatios)
        let fats = distribute(targets.fatG, ratios: fatRatios)
        return slots.enumerated().map { i, kind in
            RepartitionSlot(kind: kind, protein: proteins[i], carbs: carbs[i], fat: fats[i])
        }
    }

    // MARK: Macros pages

    /// Per-meal micronutrient score (0–100), nil when the meal carries no micro at all: the meal's
    /// daily-RDA coverage scaled up by its expected share (1 / meals today).
    static func mealNutrientScore(_ meal: MealLog, sex: MemberProfile.Sex?, mealsToday: Int) -> Int? {
        guard let coverage = MicroCoverage.overall(meals: [meal], sex: sex) else { return nil }
        let share = 1.0 / Double(max(1, mealsToday))
        return max(0, min(100, Int((Double(coverage) / share).rounded())))
    }

    /// Coverage of one nutrient, uncapped percent (the pages show 130 % when a meal overshoots).
    static func coveragePercent(consumed: Double, target: Double) -> Int {
        Int((consumed / max(target, 1) * 100).rounded())
    }

    /// Mean coverage of a group (each nutrient capped at 100 %), 0–100.
    static func groupCoverage(_ group: NutrientCatalog.GroupKey, sex: MemberProfile.Sex?, consumed: [String: Double]) -> Int {
        let ns = NutrientCatalog.nutrients(in: group)
        guard !ns.isEmpty else { return 0 }
        let total = ns.reduce(0.0) { $0 + min((consumed[$1.key] ?? 0) / $1.target(sex: sex), 1) }
        return Int((total / Double(ns.count) * 100).rounded())
    }

    /// Nutrients under `threshold` of their target, worst first, at most `limit`.
    static func gaps(threshold: Double, sex: MemberProfile.Sex?, limit: Int, consumed: [String: Double]) -> [(nutrient: NutrientCatalog.Nutrient, pct: Double)] {
        NutrientCatalog.nutrients
            .map { (nutrient: $0, pct: (consumed[$0.key] ?? 0) / $0.target(sex: sex)) }
            .filter { $0.pct < threshold }
            .sorted { $0.pct < $1.pct }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Today's summary (from the day's check-in)

    struct TodaySummary: Sendable, Equatable {
        struct Metric: Sendable, Equatable, Identifiable {
            let label: String
            let value: String
            let good: Bool
            var id: String { label }
        }
        let title: String
        let note: String
        let metrics: [Metric]
    }

    /// The Expo `buildTodaySummary`, on the markers this app reads from the day row (the 0–100 v2
    /// columns: gut, energy, calm — the legacy 1–5 `digestion`/`inflammation` columns are empty on CM OS).
    /// Nil until today's functional check-in is done.
    static func todaySummary(checkin: DailyCheckin?, mealsCount: Int) -> TodaySummary? {
        guard let checkin, checkin.isFunctionalDone else { return nil }
        let gut = checkin.gutOverall
        let digestionSignal = (gut ?? 0) >= 67 ? String(localized: "summary.digestion.steady", defaultValue: "steady") : (gut ?? 0) >= 45 ? String(localized: "summary.digestion.mixed", defaultValue: "mixed") : String(localized: "summary.digestion.fragile", defaultValue: "fragile")
        let calm = checkin.calmness
        let calmSignal = (calm ?? 0) >= 67 ? String(localized: "summary.calm.calmer", defaultValue: "calm") : (calm ?? 0) >= 45 ? String(localized: "summary.calm.moderate", defaultValue: "moderate") : String(localized: "summary.calm.reactive", defaultValue: "tense")
        let note = gut == nil
            ? String(localized: "summary.note.noGut", defaultValue: "The day felt \(calmSignal). You logged \(mealsCount) meal(s) today. Complete the gut check-in to add digestion.")
            : String(localized: "summary.note", defaultValue: "Digestion felt \(digestionSignal), the day felt \(calmSignal). You logged \(mealsCount) meal(s) today.")
        var metrics: [TodaySummary.Metric] = []
        if let gut { metrics.append(TodaySummary.Metric(label: String(localized: "summary.metric.digestion", defaultValue: "Digestion"), value: "\(gut)", good: gut >= 67)) }
        if let calm { metrics.append(TodaySummary.Metric(label: String(localized: "summary.metric.calm", defaultValue: "Calm"), value: "\(calm)", good: calm >= 67)) }
        if let energy = checkin.energy { metrics.append(TodaySummary.Metric(label: String(localized: "summary.metric.energy", defaultValue: "Energy"), value: "\(energy)", good: energy >= 67)) }
        return TodaySummary(title: String(localized: "summary.title", defaultValue: "Today at a glance"), note: note, metrics: metrics)
    }
}

/// What the targets page writes to `nb_patient_app_profiles` (the Expo `handleValidate`): the inputs
/// always; the targets ONLY when the member hand-tuned grams (`macrosCustomized`) — otherwise the DB
/// trigger sizes them from tdee + the offset and the row stays internally consistent.
struct NutritionProfileWrite: Encodable, Sendable, Equatable {
    var appSex: String
    var appAge: Int?
    var appHeightCm: Double
    var appWeightKg: Double
    /// Omitted when nil (keeps the stored value; Harris-Benedict on both sides).
    var estimatedBodyFatPercent: Double?
    var activityLevel: String?
    var goalMode: String
    var macrosCustomized: Bool
    /// Written as an explicit null when nil (the member cleared them).
    var mealsPerDay: Int?
    var snacksPerDay: Int?
    var customCalorieOffsetKcal: Int?
    /// Only on a customized row.
    var targetCalories: Int?
    var targetProteinG: Int?
    var targetCarbsG: Int?
    var targetFatG: Int?
    var tdeeKcal: Int?

    enum CodingKeys: String, CodingKey {
        case appSex, appAge, appHeightCm, appWeightKg, estimatedBodyFatPercent, activityLevel, goalMode, macrosCustomized
        case mealsPerDay, snacksPerDay, customCalorieOffsetKcal, targetCalories, targetProteinG, targetCarbsG, targetFatG, tdeeKcal
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(appSex, forKey: .appSex)
        try c.encodeIfPresent(appAge, forKey: .appAge)
        try c.encode(appHeightCm, forKey: .appHeightCm)
        try c.encode(appWeightKg, forKey: .appWeightKg)
        try c.encodeIfPresent(estimatedBodyFatPercent, forKey: .estimatedBodyFatPercent)
        try c.encodeIfPresent(activityLevel, forKey: .activityLevel)
        try c.encode(goalMode, forKey: .goalMode)
        try c.encode(macrosCustomized, forKey: .macrosCustomized)
        try c.encode(mealsPerDay, forKey: .mealsPerDay)
        try c.encode(snacksPerDay, forKey: .snacksPerDay)
        try c.encode(customCalorieOffsetKcal, forKey: .customCalorieOffsetKcal)
        if macrosCustomized {
            try c.encodeIfPresent(targetCalories, forKey: .targetCalories)
            try c.encodeIfPresent(targetProteinG, forKey: .targetProteinG)
            try c.encodeIfPresent(targetCarbsG, forKey: .targetCarbsG)
            try c.encodeIfPresent(targetFatG, forKey: .targetFatG)
            try c.encodeIfPresent(tdeeKcal, forKey: .tdeeKcal)
        }
    }
}
