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

    let title: String
    /// "September 2026" or "" when the plan has no start date.
    let startDate: String
    let practitioner: String
    let goals: [String]
    let sections: [Section]
}

/// One `care_plans` row the member may read.
struct CarePlanRow: Decodable, Sendable, Equatable {
    let id: String
    let title: String?
    let startDate: String?
    let status: String?
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
        for (i, row) in rows.enumerated() {
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

    static func assemble(plan: CarePlanRow, items: [CarePlanItemRow]) -> CarePlan {
        let title = (plan.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return CarePlan(
            title: title.isEmpty ? String(localized: "careplan.fallbackTitle", defaultValue: "Care plan") : title,
            startDate: formatStartDate(plan.startDate),
            practitioner: String(localized: "careplan.practitioner", defaultValue: "Your practitioner"),
            goals: buildGoals(items),
            sections: buildSections(items)
        )
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
