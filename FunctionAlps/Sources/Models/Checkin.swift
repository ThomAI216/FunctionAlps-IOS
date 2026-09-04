import Foundation

/// The moment of day a check-in belongs to (`patient_checkin_moments.slot`).
/// Same vocabulary and hour boundaries as the Expo app's `lib/plan/slots.ts`.
enum MomentSlot: String, Sendable, Hashable, CaseIterable {
    case morning, midday, evening

    static let order: [MomentSlot] = [.morning, .midday, .evening]
    var rank: Int { Self.order.firstIndex(of: self) ?? 0 }

    /// `<11` morning, `11–16` midday, `>=17` evening (patient-local hour).
    static func current(hour: Int) -> MomentSlot {
        if hour < 11 { return .morning }
        if hour < 17 { return .midday }
        return .evening
    }

    var glyph: String {
        switch self {
        case .morning: "☀"
        case .midday: "◐"
        case .evening: "☾"
        }
    }

    var localizedName: String {
        switch self {
        case .morning: String(localized: "slot.morning", defaultValue: "Morning")
        case .midday: String(localized: "slot.midday", defaultValue: "Midday")
        case .evening: String(localized: "slot.evening", defaultValue: "Evening")
        }
    }
}

enum DimKey: String, Sendable, Hashable, CaseIterable {
    case energy, sleep, mood, stress
}

/// Sleep's non-slider answers. `durationMin` is written only once the member touched the times.
struct SleepSpecials: Sendable, Equatable {
    var bedTime: String? = nil       // "HH:mm"
    var wakeTime: String? = nil      // "HH:mm"
    var durationMin: Int? = nil
    var latency: String? = nil       // lt_15 | 15_30 | 30_60 | gt_60
    var wakeCount: String? = nil     // 0 | 1_2 | 3plus
}

/// One dimension's editable answers (mirrors the Expo `DimAnswers`): sliders 0–100,
/// pills = group key → selected option keys, specials = sleep only.
struct DimAnswers: Sendable, Equatable {
    var sliders: [String: Double] = [:]
    var pills: [String: [String]] = [:]
    var specials = SleepSpecials()

    static let empty = DimAnswers()
}

typealias FunctionalAnswers = [DimKey: DimAnswers]

extension Dictionary where Key == DimKey, Value == DimAnswers {
    static var blank: FunctionalAnswers {
        Dictionary(uniqueKeysWithValues: DimKey.allCases.map { ($0, DimAnswers.empty) })
    }
}

/// One saved check-in moment = one `patient_checkin_moments` row, unique per (patient, day, slot).
/// ⚠ MARKER CONTRACT: every marker is 0–100, HIGHER = BETTER. `stressScore` stores CALMNESS. Never invert.
/// Pills are stored-not-scored: self-reported context kept verbatim, never a health signal.
struct CheckinMoment: Sendable, Equatable {
    let slot: MomentSlot
    let submittedAt: Date
    var energyBody: Int? = nil
    var energyMind: Int? = nil
    var energyStability: Int? = nil
    var energyOverall: Int? = nil
    var moodScore: Int? = nil
    var stressScore: Int? = nil
    var sleepOverall: Int? = nil
    var sleepRefreshed: Int? = nil
    var sleepDurationMin: Int? = nil
    var sleepLatencyBand: String? = nil
    var sleepWakeCount: String? = nil
    var pills: [String: [String]] = [:]
    var note: String? = nil

    var hasSleep: Bool {
        sleepOverall != nil || sleepRefreshed != nil || sleepDurationMin != nil || sleepLatencyBand != nil || sleepWakeCount != nil
    }
}

/// The values that roll up into the ONE day-summary row (`patient_daily_checkins`).
struct DaySummary: Sendable, Equatable {
    var energyOverall: Int? = nil
    var energyBody: Int? = nil
    var energyMind: Int? = nil
    var moodScore: Int? = nil
    var stressScore: Int? = nil
    var sleepOverall: Int? = nil
    var sleepRefreshed: Int? = nil
    var sleepDurationMin: Int? = nil
    var sleepLatencyBand: String? = nil
    var sleepWakeCount: String? = nil
    var momentCount = 0

    var hasSleep: Bool {
        sleepOverall != nil || sleepRefreshed != nil || sleepDurationMin != nil || sleepLatencyBand != nil || sleepWakeCount != nil
    }
}

/// What the day row already holds — read BEFORE the summary write so a computed null
/// never wipes a value another writer put there (the no-wipe invariant).
struct DailyCheckinCarry: Sendable, Equatable {
    var recovery: Int? = nil
    var soreness: Int? = nil
    var recentLoad: Int? = nil
    var recentMentalLoad: Int? = nil
    var energyBody: Int? = nil
    var energyMind: Int? = nil
    var energyStability: Int? = nil
    var energyOverall: Int? = nil
    var moodScore: Int? = nil
    var stressScore: Int? = nil
    var sleepOverall: Int? = nil
    var sleepRefreshed: Int? = nil
    var sleepDurationMin: Int? = nil
    var sleepLatencyBand: String? = nil
    var sleepWakeCount: String? = nil
    var energy: Int? = nil
    var mood: Int? = nil
    var sleep: Int? = nil
    var stress: Int? = nil
}

/// The `patient_daily_checkins` patch for today. `sleep == nil` means EVERY sleep column is
/// left out of the write, so a midday moment can never null out the morning's night.
struct DaySummaryPatch: Sendable, Equatable {
    struct Sleep: Sendable, Equatable {
        var sleepOverall: Int? = nil
        var sleepRefreshed: Int? = nil
        var sleepDurationMin: Int? = nil
        var sleepLatencyBand: String? = nil
        var sleepWakeCount: String? = nil
        var legacySleep: Int? = nil
    }

    var energyBody: Int? = nil
    var energyMind: Int? = nil
    var energyStability: Int? = nil
    var energyOverall: Int? = nil
    var moodScore: Int? = nil
    var stressScore: Int? = nil
    var legacyEnergy: Int? = nil
    var legacyMood: Int? = nil
    var legacyStress: Int? = nil
    var recovery: Int? = nil
    var soreness: Int? = nil
    var recentLoad: Int? = nil
    var recentMentalLoad: Int? = nil
    var sleep: Sleep? = nil
    let completedAt: Date
}

/// One `nb_checkin_events` row (`source = 'daily'`).
struct CheckinEvent: Sendable, Equatable {
    let dimension: String
    let value: Int
    let ts: Date
}

/// A column value with an EXPLICIT null — PostgREST's merge-duplicates upsert updates every
/// key present in the body, so "clear this" and "leave this" must be spelled differently.
enum ColumnValue: Sendable, Equatable, Encodable {
    case int(Int)
    case string(String)
    case null
    case pills([String: [String]])
    /// A jsonb column whose keys must travel verbatim (`JSONValue`).
    case json(JSONValue)

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .json(let j): try j.encode(to: encoder)
        default:
            var c = encoder.singleValueContainer()
            switch self {
            case .int(let v): try c.encode(v)
            case .string(let s): try c.encode(s)
            case .null: try c.encodeNil()
            case .pills(let p): try c.encode(p)
            case .json: break
            }
        }
    }

    static func int(_ v: Int?) -> ColumnValue { v.map { .int($0) } ?? .null }
    static func string(_ s: String?) -> ColumnValue { s.map { .string($0) } ?? .null }
}

typealias ColumnPatch = [String: ColumnValue]
