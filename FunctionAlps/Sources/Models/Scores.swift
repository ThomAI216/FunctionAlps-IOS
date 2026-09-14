import Foundation

/// The server-computed scores (`member-scores` edge function = the Expo engine, verbatim).
/// The app never scores; it renders these (PRD §41).
struct ScoreFactor: Sendable, Equatable, Decodable, Identifiable {
    let key: String
    let label: String
    let value: Double?
    let weight: Double
    let status: String   // good | watch | bad
    let detail: String?
    var id: String { key }
    var intValue: Int? { value.map { Int($0.rounded()) } }
}

struct ScoreTip: Sendable, Equatable, Decodable {
    let summary: String
    let good: String
    let bad: String

    /// `summary` is a template with a `{label}` placeholder (score-tip.ts).
    func summaryText(label: String) -> String { summary.replacingOccurrences(of: "{label}", with: label) }
}

struct ScoreBreakdown: Sendable, Equatable, Decodable {
    let score: Double?
    let factors: [ScoreFactor]
    let series14d: [Double?]
    let tip: ScoreTip?
    var intScore: Int? { score.map { Int($0.rounded()) } }
    var intSeries: [Int?] { series14d.map { $0.map { Int($0.rounded()) } } }
}

struct Composite: Sendable, Equatable, Decodable {
    struct Pillars: Sendable, Equatable, Decodable {
        let vitality: Double?
        let metabolic: Double?
        let nutrition: Double?
    }
    let score: Double?
    let basis: String
    let pillars: Pillars
    var intScore: Int? { score.map { Int($0.rounded()) } }
}

struct MemberScores: Sendable, Equatable, Decodable {
    enum Trend: String, Sendable, Decodable { case up, down, flat }

    let day: String
    let trend: Trend?
    let composite: Composite
    let vitality: ScoreBreakdown
    let metabolic: ScoreBreakdown
    let nutrition: ScoreBreakdown
    let gut: ScoreBreakdown
    let compositeSeries14d: [Double?]
    /// How the wearable inputs were built server-side (Phase 4): the HRV level, the source per metric, the
    /// baseline days. Optional — absent on older servers, `{error}` when the read failed (every field nil).
    let wearable: WearableInputSummary?

    var crownSeries: [Int?] { compositeSeries14d.map { $0.map { Int($0.rounded()) } } }

    enum Pillar: String, CaseIterable, Sendable {
        case vitality, metabolic, nutrition
        var title: String {
            switch self {
            case .vitality: String(localized: "pillar.vitality", defaultValue: "Vitality")
            case .metabolic: String(localized: "pillar.metabolic", defaultValue: "Metabolic")
            case .nutrition: String(localized: "pillar.nutrition", defaultValue: "Nutrition")
            }
        }
        var caption: String {
            switch self {
            case .vitality: String(localized: "pillar.vitality.caption", defaultValue: "How you feel & show up")
            case .metabolic: String(localized: "pillar.metabolic.caption", defaultValue: "How your engine runs on fuel")
            case .nutrition: String(localized: "pillar.nutrition.caption", defaultValue: "How well you fuel")
            }
        }
        /// PILLAR_TINT — the pastel trio the home card and the crown share.
        var tintHex: UInt32 {
            switch self {
            case .vitality: 0xE6CF85
            case .metabolic: 0xE0A0A0
            case .nutrition: 0xA6C2E0
            }
        }
    }

    func breakdown(_ pillar: Pillar) -> ScoreBreakdown {
        switch pillar {
        case .vitality: vitality
        case .metabolic: metabolic
        case .nutrition: nutrition
        }
    }
}

/// `member-scores.wearable` — never a vendor score, never a judgement: which device feeds which signal and how
/// many days the member's own baseline stands on.
struct WearableInputSummary: Sendable, Equatable, Decodable {
    struct Metric: Sendable, Equatable, Decodable {
        let source: String?
        let days: Int?
        let baselineDays: Int?
        let baseline: Double?
        let eligible: Bool?
    }
    let hrvMetric: String?
    let hrv: Metric?
    let restingHr: Metric?
    let sleep: Metric?
    let steps: Metric?
    let daysWithData: Int?
    let sources: [String]?

    /// A device name a member recognises (`whoop` → "WHOOP", `apple_health` → "Apple Health").
    static func displayName(_ source: String) -> String {
        switch source {
        case "apple_health": "Apple Health"
        case "health_connect": "Health Connect"
        case "whoop": "WHOOP"
        case "oura": "Oura"
        case "polar": "Polar"
        case "garmin": "Garmin"
        case "withings": "Withings"
        case "suunto": "Suunto"
        case "google": "Google (Fitbit)"
        case "thryve": "linked device"
        default: source
        }
    }

    /// The one line under "Body signals": where the recovery signals come from and whether the baseline is ready.
    var caption: String? {
        guard let hrv, let source = hrv.source else { return nil }
        let name = Self.displayName(source)
        let days = hrv.baselineDays ?? 0
        if hrv.eligible == true {
            return String(localized: "scores.wearable.ready", defaultValue: "Recovery signals from \(name) · \(days)-day baseline")
        }
        return String(localized: "scores.wearable.building", defaultValue: "Recovery signals from \(name) · baseline in \(max(0, 14 - days)) more days")
    }
}
