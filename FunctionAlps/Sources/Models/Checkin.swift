import Foundation

/// The moment of day a check-in belongs to (`patient_checkin_moments.slot`).
/// Two moments are asked for: MORNING (the night behind you and the day ahead) and EVENING (the day
/// you just lived). `midday` is kept because the column vocabulary and older rows still carry it —
/// it is never scheduled and never offered, only read back and editable.
enum MomentSlot: String, Sendable, Hashable, CaseIterable {
    case morning, midday, evening

    /// Day order, midday included — a legacy row must still sort between the two.
    static let order: [MomentSlot] = [.morning, .midday, .evening]
    /// The moments the app asks for: one on waking, one before bed.
    static let scheduled: [MomentSlot] = [.morning, .evening]
    var rank: Int { Self.order.firstIndex(of: self) ?? 0 }

    /// Which moment "now" belongs to: the day is the morning's until the evening reflection is due.
    /// `<17` morning, `>=17` evening (patient-local hour).
    static func current(hour: Int) -> MomentSlot {
        hour < 17 ? .morning : .evening
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

    /// Minutes past midnight for `HH:mm`, wrapping into the day; junk → nil.
    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return ((parts[0] * 60 + parts[1]) % 1440 + 1440) % 1440
    }

    /// Length of the night, wrapping past midnight (bed 22:00 → wake 06:30 = 510).
    static func windowMinutes(bed: String, wake: String) -> Int? {
        guard let b = minutes(bed), let w = minutes(wake) else { return nil }
        return (w - b + 1440) % 1440
    }

    /// A postgres `time` as PostgREST sends it (`'22:15:00'`, sometimes `'22:15'`) → `HH:mm`; junk → nil.
    static func clock(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let head = String(raw.prefix(5))
        let parts = head.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return String(format: "%02d:%02d", h, m)
    }
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
    /// The night's wall clock, `HH:mm` — what duration is the length of. Kept, not just measured.
    var sleepBedTime: String? = nil
    var sleepWakeTime: String? = nil
    var pills: [String: [String]] = [:]
    var note: String? = nil

    var hasSleep: Bool {
        sleepOverall != nil || sleepRefreshed != nil || sleepDurationMin != nil || sleepLatencyBand != nil || sleepWakeCount != nil
            || sleepBedTime != nil || sleepWakeTime != nil
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
    var sleepBedTime: String? = nil
    var sleepWakeTime: String? = nil
    var momentCount = 0

    var hasSleep: Bool {
        sleepOverall != nil || sleepRefreshed != nil || sleepDurationMin != nil || sleepLatencyBand != nil || sleepWakeCount != nil
            || sleepBedTime != nil || sleepWakeTime != nil
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
    var sleepBedTime: String? = nil
    var sleepWakeTime: String? = nil
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
        var sleepBedTime: String? = nil
        var sleepWakeTime: String? = nil
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
    case bool(Bool)
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
            case .bool(let b): try c.encode(b)
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

// MARK: - Red flags (patient_daily_checkins.red_flag_*)

/// The six red-flag symptoms on `patient_daily_checkins` (`red_flag_*`) — the Expo `red-flags.ts` list.
/// Asked by the gut check-in, stored as booleans, NEVER scored. When any is true the member sees the
/// signpost (a doctor's eye, not a nutrition read) and one `red_flag` event reaches the practitioner side.
enum RedFlag: String, Sendable, Hashable, CaseIterable, Identifiable {
    case bloodInStool = "blood_in_stool"
    case blackStool = "black_stool"
    case persistentVomiting = "persistent_vomiting"
    case fever
    case unintentionalWeightLoss = "unintentional_weight_loss"
    case severeWorseningPain = "severe_worsening_pain"

    var id: String { rawValue }
    var column: String { "red_flag_" + rawValue }

    var label: String {
        switch self {
        case .bloodInStool: String(localized: "redflag.blood_in_stool", defaultValue: "Blood in stool")
        case .blackStool: String(localized: "redflag.black_stool", defaultValue: "Black stool")
        case .persistentVomiting: String(localized: "redflag.persistent_vomiting", defaultValue: "Persistent vomiting")
        case .fever: String(localized: "redflag.fever", defaultValue: "Fever")
        case .unintentionalWeightLoss: String(localized: "redflag.unintentional_weight_loss", defaultValue: "Unintentional weight loss")
        case .severeWorseningPain: String(localized: "redflag.severe_worsening_pain", defaultValue: "Severe or worsening pain")
        }
    }
}

struct RedFlags: Sendable, Equatable, Hashable {
    var raised: Set<RedFlag> = []

    static let none = RedFlags()
    var any: Bool { !raised.isEmpty }
    func contains(_ flag: RedFlag) -> Bool { raised.contains(flag) }
    mutating func toggle(_ flag: RedFlag) {
        if raised.contains(flag) { raised.remove(flag) } else { raised.insert(flag) }
    }

    /// From the six `red_flag_*` booleans — a missing or null column is "not raised".
    static func from(_ column: (RedFlag) -> Bool?) -> RedFlags {
        RedFlags(raised: Set(RedFlag.allCases.filter { column($0) == true }))
    }

    /// The member-facing signpost, verbatim from the Expo app (`RED_FLAG_SIGNPOST`). Never a diagnosis.
    static var signpost: String {
        String(localized: "redflag.signpost", defaultValue: "Some of what you logged · like blood in your stool or persistent vomiting · is worth discussing with a doctor. FunctionAlps is a wellness mirror, not a medical service.")
    }
}

// MARK: - The moment submission (member_submit_checkin v2)

/// What the phone SENDS for a moment: the RAW answers. The server scores them (`member_submit_checkin` v2,
/// `checkin_energy_overall` / `checkin_sleep_overall`) so every client agrees to the point; `CheckinEngine`
/// stays the tested reference of that scoring and still guards "nothing answered → nothing sent".
struct CheckinSubmission: Sendable, Equatable {
    let submittedAt: Date
    let answers: FunctionalAnswers
    let pills: [String: [String]]
    let note: String?
}

/// What comes back: the row as the SERVER scored it, plus the day's red flags for the signpost.
struct CheckinSubmitResult: Sendable, Equatable {
    let moment: CheckinMoment
    let momentCount: Int
    let scoredBy: String
    let redFlags: RedFlags
}
