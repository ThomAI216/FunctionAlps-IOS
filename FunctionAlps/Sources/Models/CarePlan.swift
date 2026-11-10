import Foundation

/// The member's real care plan from CM OS (`care_plans` + `care_plan_items`, member-read RLS).
/// The Expo `lib/care-plan/use-care-plan.ts` shape: one header, the distinct objectives as goals,
/// the items grouped by domain into sections.
struct CarePlan: Sendable, Equatable {
    struct Item: Sendable, Equatable, Identifiable {
        enum Status: String, Sendable { case active, completed, paused }
        let id: String
        let text: String
        let status: Status
    }

    struct Section: Sendable, Equatable, Identifiable {
        let category: String
        /// SF Symbol standing in for the lucide icon.
        let symbol: String
        let colorHex: UInt32
        let items: [Item]
        var id: String { category }
    }

    /// A goal the clinician set, with — where they wrote them — where the member starts and where they aim.
    struct Goal: Sendable, Equatable, Identifiable {
        let id: String
        let statement: String
        /// The phase it belongs to; nil = the whole plan.
        let phaseKey: String?
        let baseline: Double?
        let target: Double?
        let unit: String?
        let cadence: String?
    }

    /// What · how much · when · why (the "why" is the point).
    struct Supplement: Sendable, Equatable, Identifiable {
        let id: String
        let name: String
        let dosage: String?
        let timing: String?
        let why: String?
    }

    /// A test that was actually ordered (a `proposed` order never reaches the member).
    struct Test: Sendable, Equatable, Identifiable {
        enum State: String, Sendable { case ordered, processing, resulted }
        let id: String
        let name: String
        let state: State
    }

    let title: String
    /// "September 2026" or "" when the plan has no start date.
    let startDate: String
    let practitioner: String
    let goals: [String]
    let sections: [Section]
    // The clinician's plan page, member-safe (owner, 2026-11-10: "more about the objective, the journey, the
    // priorities"): the same blocks as CLINICAL → patient → Plan, the members web `getMemberCarePlan` reads.
    /// `care_plans.objective_line` — the one sentence the app leads with.
    var objectiveLine: String? = nil
    /// `care_plans.approach_md` — the clinician's "how we'll get there", in their words.
    var approach: String? = nil
    var planGoals: [Goal] = []
    var supplements: [Supplement] = []
    var tests: [Test] = []
    /// `care_plans.review_date`, formatted ("12 December 2026").
    var reviewDate: String? = nil
    /// `care_plans.expectations_md` — what to expect between now and the review.
    var expectations: String? = nil
}

/// One `care_plans` row the member may read.
struct CarePlanRow: Decodable, Sendable, Equatable {
    let id: String
    let title: String?
    let startDate: String?
    let status: String?
    var objectiveLine: String? = nil
    var approachMd: String? = nil
    var reviewDate: String? = nil
}

/// `care_plans.expectations_md`, read on its own: the column is newer than some schemas, and a missing column
/// must only hide the block, never the plan.
struct CarePlanExpectationsRow: Decodable, Sendable, Equatable {
    let expectationsMd: String?
}

/// One `care_plan_goals` row (RLS: own, active, patient-visible — filtered again in the query).
struct CarePlanGoalRow: Decodable, Sendable, Equatable {
    let id: String
    let statement: String?
    let phaseKey: String?
    let baselineValue: Double?
    let targetValue: Double?
    let targetUnit: String?
    let cadenceText: String?
}

/// One `supplement_plans` row: the clinician's own words for how much and when.
struct SupplementPlanRow: Decodable, Sendable, Equatable {
    let carePlanItemId: String?
    let dosageText: String?
    let frequencyText: String?
    let status: String?
}

/// One `test_orders` row with its catalogue name (`notes` is clinician-internal and never selected).
struct TestOrderRow: Decodable, Sendable, Equatable {
    struct Catalog: Decodable, Sendable, Equatable {
        let name: String?
        let shortName: String?
    }
    let id: String
    let testType: String?
    let status: String
    let diagnosticTests: Catalog?
}

/// One `care_plan_items` row (RLS already limits to patient-visible + pushed/approved).
struct CarePlanItemRow: Decodable, Sendable, Equatable {
    let id: String
    let domain: String?
    let title: String?
    let objective: String?
    let instructionText: String?
    let patientSafeExplanation: String?
    let status: String?
    let sortOrder: Int?
    var itemKind: String? = nil
    var cadence: String? = nil
    var frequencyText: String? = nil
    var doseValue: Double? = nil
    var doseUnit: String? = nil

    /// A supplement line — it has its own card, never the "plan in detail" list.
    var isSupplement: Bool { itemKind == "supplement_plan" || domain == "supplementation" }
}

/// Pure rules — the Expo `buildSections` / `buildGoals` / `uiStatus` / `itemText`, line for line.
enum CarePlanLogic {
    struct DomainMeta: Sendable { let label: String; let symbol: String; let colorHex: UInt32 }

    private static let forest: UInt32 = 0x4A8A5C
    static let domainMeta: [String: DomainMeta] = [
        "nutrition": .init(label: "Nutrition", symbol: "fork.knife", colorHex: forest),
        "meal_timing": .init(label: "Nutrition", symbol: "fork.knife", colorHex: forest),
        "elimination_diet": .init(label: "Nutrition", symbol: "fork.knife", colorHex: forest),
        "digestive_support": .init(label: "Digestive support", symbol: "leaf", colorHex: forest),
        "hydration": .init(label: "Hydration", symbol: "leaf", colorHex: forest),
        "supplementation": .init(label: "Supplements", symbol: "pills", colorHex: 0xA98FD0),
        "exercise": .init(label: "Movement", symbol: "figure.walk", colorHex: forest),
        "sleep": .init(label: "Sleep", symbol: "moon", colorHex: 0x6D7FB0),
        "stress_regulation": .init(label: "Stress", symbol: "brain", colorHex: 0xB08A6D),
        "behavior_change": .init(label: "Lifestyle", symbol: "figure.walk", colorHex: forest),
        "symptom_monitoring": .init(label: "Monitoring", symbol: "heart", colorHex: 0xC97D8A),
        "biomarker_follow_up": .init(label: "Monitoring", symbol: "heart", colorHex: 0xC97D8A),
        "education": .init(label: "Education", symbol: "brain", colorHex: forest),
        "referral": .init(label: "Referrals", symbol: "heart", colorHex: 0xC97D8A),
    ]
    static let fallbackMeta = DomainMeta(label: "Plan", symbol: "figure.walk", colorHex: forest)

    /// The clinical lifecycle → the 3-state badge. RLS only ever shows pushed_to_app / approved.
    static func uiStatus(_ raw: String?) -> CarePlan.Item.Status {
        switch raw {
        case "resolved", "archived": return .completed
        case "superseded", "dismissed": return .paused
        default: return .active
        }
    }

    /// The line the member reads: instruction, else the patient-safe explanation, else title/objective.
    static func itemText(_ row: CarePlanItemRow) -> String {
        for candidate in [row.instructionText, row.patientSafeExplanation, row.title, row.objective] {
            if let c = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        }
        return ""
    }

    static func buildSections(_ rows: [CarePlanItemRow]) -> [CarePlan.Section] {
        var order: [String] = []
        var byLabel: [String: (meta: DomainMeta, items: [CarePlan.Item])] = [:]
        for (i, row) in rows.enumerated() where !row.isSupplement {
            let text = itemText(row)
            guard !text.isEmpty else { continue }
            let meta = domainMeta[row.domain ?? ""] ?? fallbackMeta
            if byLabel[meta.label] == nil {
                byLabel[meta.label] = (meta, [])
                order.append(meta.label)
            }
            byLabel[meta.label]?.items.append(CarePlan.Item(id: row.id.isEmpty ? String(i) : row.id, text: text, status: uiStatus(row.status)))
        }
        return order.compactMap { label in
            guard let entry = byLabel[label], !entry.items.isEmpty else { return nil }
            return CarePlan.Section(category: entry.meta.label, symbol: entry.meta.symbol, colorHex: entry.meta.colorHex, items: entry.items)
        }
    }

    /// The distinct per-item objectives, in row order.
    static func buildGoals(_ rows: [CarePlanItemRow]) -> [String] {
        var seen = Set<String>()
        var goals: [String] = []
        for row in rows {
            let objective = (row.objective ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !objective.isEmpty, !seen.contains(objective) {
                seen.insert(objective)
                goals.append(objective)
            }
        }
        return goals
    }

    /// "2026-09-01" → "September 2026" (the Expo `en-GB` month + year).
    static func formatStartDate(_ raw: String?, locale: Locale = .current) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(raw.prefix(10))) else { return "" }
        let out = DateFormatter()
        out.locale = locale
        out.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return out.string(from: date)
    }

    static func assemble(plan: CarePlanRow, items: [CarePlanItemRow], goals: [CarePlanGoalRow] = [], supplementPlans: [SupplementPlanRow] = [],
                         tests: [TestOrderRow] = [], expectations: String? = nil) -> CarePlan {
        let title = (plan.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var out = CarePlan(
            title: title.isEmpty ? String(localized: "careplan.fallbackTitle", defaultValue: "Care plan") : title,
            startDate: formatStartDate(plan.startDate),
            practitioner: String(localized: "careplan.practitioner", defaultValue: "Your practitioner"),
            goals: buildGoals(items.filter { !$0.isSupplement }),
            sections: buildSections(items)
        )
        out.objectiveLine = trimmed(plan.objectiveLine)
        out.approach = trimmed(plan.approachMd)
        out.planGoals = buildPlanGoals(goals)
        out.supplements = buildSupplements(items.filter(\.isSupplement), plans: supplementPlans)
        out.tests = buildTests(tests)
        out.reviewDate = formatDay(plan.reviewDate)
        out.expectations = trimmed(expectations)
        return out
    }

    static func trimmed(_ raw: String?) -> String? {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    static func buildPlanGoals(_ rows: [CarePlanGoalRow]) -> [CarePlan.Goal] {
        rows.compactMap { row in
            guard let statement = trimmed(row.statement) else { return nil }
            return CarePlan.Goal(id: row.id, statement: statement, phaseKey: trimmed(row.phaseKey), baseline: row.baselineValue,
                                 target: row.targetValue, unit: trimmed(row.targetUnit), cadence: trimmed(row.cadenceText))
        }
    }

    /// The goals that apply now: plan-wide ones and the current phase's. No current phase (no start date, or the
    /// arc has run out) → every goal, rather than an empty block (the members web `goalsForPhase`).
    static func goalsNow(_ goals: [CarePlan.Goal], currentPhase: String?) -> [CarePlan.Goal] {
        guard let currentPhase else { return goals }
        return goals.filter { $0.phaseKey == nil || $0.phaseKey == currentPhase }
    }

    /// "5 → 8 /10" — where the member starts and where the plan aims, when the clinician wrote them.
    static func goalRange(_ goal: CarePlan.Goal) -> String? {
        func n(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
        let unit = goal.unit.map { " \($0)" } ?? ""
        switch (goal.baseline, goal.target) {
        case let (b?, t?): return "\(n(b)) → \(n(t))\(unit)"
        case let (nil, t?): return String(localized: "careplan.goal.target", defaultValue: "Target \(n(t))\(unit)")
        default: return nil
        }
    }

    /// Supplements with their plan row's dosage and timing. A plan the clinician STOPPED or PAUSED drops the
    /// supplement: the item can outlive the decision, and showing it as current would change what someone swallows.
    static func buildSupplements(_ items: [CarePlanItemRow], plans: [SupplementPlanRow]) -> [CarePlan.Supplement] {
        var byItem: [String: SupplementPlanRow] = [:]
        for plan in plans { if let id = plan.carePlanItemId { byItem[id] = plan } }
        return items.compactMap { item in
            let plan = byItem[item.id]
            if let status = plan?.status, status != "active", status != "planned" { return nil }
            guard let name = trimmed(item.title) ?? trimmed(item.instructionText) else { return nil }
            let dose = [item.doseValue.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }, trimmed(item.doseUnit)]
                .compactMap { $0 }.joined(separator: " ")
            return CarePlan.Supplement(id: item.id, name: name, dosage: trimmed(plan?.dosageText) ?? trimmed(dose),
                                       timing: trimmed(plan?.frequencyText) ?? trimmed(item.cadence) ?? trimmed(item.frequencyText),
                                       why: trimmed(item.patientSafeExplanation))
        }
    }

    /// `ordered` → ordered · `pending`/`received` → processing · `reviewed` → resulted. `proposed` (an AI
    /// suggestion never ordered) and `cancelled` never reach the member.
    static func testState(_ status: String) -> CarePlan.Test.State? {
        switch status {
        case "ordered": .ordered
        case "pending", "received": .processing
        case "reviewed": .resulted
        default: nil
        }
    }

    static func buildTests(_ rows: [TestOrderRow]) -> [CarePlan.Test] {
        rows.compactMap { row in
            guard let state = testState(row.status),
                  let name = trimmed(row.diagnosticTests?.name) ?? trimmed(row.testType) else { return nil }
            return CarePlan.Test(id: row.id, name: name, state: state)
        }
    }

    /// "2026-12-12" → "12 December 2026".
    static func formatDay(_ raw: String?, locale: Locale = .current) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(raw.prefix(10))) else { return nil }
        let out = DateFormatter()
        out.locale = locale
        out.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return out.string(from: date)
    }
}

/// `nb_patient_app_profiles.current_complaints` keys → labels (the Expo `COMPLAINT_LABELS`).
enum ComplaintLabels {
    static func label(_ key: String) -> String {
        switch key {
        case "fatigue": String(localized: "complaint.fatigue", defaultValue: "Fatigue")
        case "bloating": String(localized: "complaint.bloating", defaultValue: "Bloating")
        case "brain_fog": String(localized: "complaint.brain_fog", defaultValue: "Brain fog")
        case "poor_sleep": String(localized: "complaint.poor_sleep", defaultValue: "Poor sleep")
        case "weight_gain": String(localized: "complaint.weight_gain", defaultValue: "Weight gain")
        case "low_energy": String(localized: "complaint.low_energy", defaultValue: "Low energy")
        case "digestive_issues": String(localized: "complaint.digestive_issues", defaultValue: "Digestive issues")
        case "skin_issues": String(localized: "complaint.skin_issues", defaultValue: "Skin issues")
        default: key.replacingOccurrences(of: "_", with: " ")
        }
    }
}
