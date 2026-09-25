import Foundation

// ⚠ WIRE SHAPES. This file spells CM OS column names, and repo rule 2 says only
// `Core/API/*` may know them. It is drafted here only because this feature's
// drafts are confined to `Features/StressTrack/`. When wiring, MOVE THIS FILE, as
// it is, to `Core/API/StressTrackWire.swift` (brief §9, step 1). Nothing else in
// the feature depends on where it lives.
//
// Table: `stress_diary_day`, migration 205 (applied on CM OS 2026-09-25).
// The column list here is asserted, column for column, against the server's own
// read in `clinical-dashboard/lib/stress/db.ts` (`STRESS_DAY_COLUMNS`).

// MARK: - ⚠ The decoding trap

/// The decoder for every Stress wire type.
///
/// **Never decode these with `JSON.decode`, `PostgRESTClient.select` or
/// `selectOne`.** The app's shared decoder uses `.convertFromSnakeCase`, which turns
/// the JSON key `am_recovered` into `amRecovered` BEFORE matching it against a
/// CodingKey. These CodingKeys are the column names verbatim (`"am_recovered"`), so
/// under that decoder every optional column would decode as nil — a skipped answer
/// indistinguishable from a real one — and every required one would throw.
///
/// So the backend reads with `PostgRESTClient.selectRaw` and decodes with this: a
/// plain decoder, no key strategy, timestamps left as the strings Postgres sent.
enum StressWire {
    static var decoder: JSONDecoder { JSONDecoder() }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(detail: String(describing: error))
        }
    }
}

// MARK: - stress_diary_day — the read shape

/// One `stress_diary_day` row: the items a running Stress track ADDS to the check-in.
///
/// **Mood and calm are not here, and must never be added.** They live in
/// `patient_checkin_moments` (`mood_score`, `stress_score`) and the server reads them
/// from there. `stress_score` stores CALMNESS (0–100, higher = calmer); a copy here
/// would be a second truth, and an inverted copy would be a stress score.
///
/// Every answer column is nullable: NULL is "not answered", never 0.
///
/// `Encodable` is synthesized and OMITS nil columns — so it is **never** an upsert
/// body. A body that omits a column leaves the stored value in place, which is how a
/// cleared answer would silently survive. Writes go through `StressDiaryWrite`.
struct StressDiaryDay: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let patientId: String
    let assessmentId: String
    /// The member's own local date. Never a UTC date.
    let localDate: String
    /// IANA zone the member was in that day.
    var timezone: String?

    /// The shared obligation/free axis. NOT written by this app — see brief §12 Q1.
    var dayType: String?
    /// NOT written by this app.
    var dayModifiers: [String]

    // Morning additions
    var amRecovered: Int?
    var amUnwell: Bool?
    var alcoholLastEvening: Bool?

    // Evening additions
    var pmPeak: Int?
    var pmRecoveryLatency: RecoveryLatencyBand?
    var pmCarryover: Int?
    var pmWorkDetachment: Int?
    var pmRestorative: Bool?
    var pmRestorativeTypes: [String]
    var pmRestorativeEffect: Int?
    var pmMeaningfulConnection: Bool?

    /// Free text. NOT written by this app (the additions ask none). If it ever is:
    /// never parsed, never summarised, never sent to a model — a person reads it.
    var note: String?

    var loggedVia: StressSurface?
    /// Postgres timestamptz, as sent. `ISO8601.parse` when a Date is needed.
    var loggedAt: String?
    var updatedVia: StressSurface?
    let createdAt: String
    var updatedAt: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case patientId = "patient_id"
        case assessmentId = "assessment_id"
        case localDate = "local_date"
        case timezone
        case dayType = "day_type"
        case dayModifiers = "day_modifiers"
        case amRecovered = "am_recovered"
        case amUnwell = "am_unwell"
        case alcoholLastEvening = "alcohol_last_evening"
        case pmPeak = "pm_peak"
        case pmRecoveryLatency = "pm_recovery_latency"
        case pmCarryover = "pm_carryover"
        case pmWorkDetachment = "pm_work_detachment"
        case pmRestorative = "pm_restorative"
        case pmRestorativeTypes = "pm_restorative_types"
        case pmRestorativeEffect = "pm_restorative_effect"
        case pmMeaningfulConnection = "pm_meaningful_connection"
        case note
        case loggedVia = "logged_via"
        case loggedAt = "logged_at"
        case updatedVia = "updated_via"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// The `select=` list, derived from the CodingKeys so the two cannot drift.
    static let columns = CodingKeys.allCases.map(\.rawValue).joined(separator: ",")
}

// MARK: - stress_diary_day — the write shape

/// The upsert body for ONE half of ONE day, on the natural key
/// `(patient_id, assessment_id, local_date)`.
///
/// PostgREST's `resolution=merge-duplicates` writes every key present in the body
/// and leaves every absent key alone. So this body carries:
///  - the natural key and the member's zone;
///  - **only its own half's columns, each one explicitly** — a skipped item is sent
///    as `null`, so clearing an answer really clears it;
///  - **none of the other half's columns** — so the morning save can never null the
///    evening's answers, or the evening the morning's, and a half answered on the web
///    survives a save of the other half here;
///  - bookkeeping: `updated_via` always; `logged_via` / `logged_at` only when this
///    app believes it is creating the row, so they keep meaning "who logged it first".
///
/// Never sent: mood, calm (not columns here, and never will be), `day_type`,
/// `day_modifiers`, `note`, `id`, `created_at`, `updated_at` (a trigger sets it).
///
/// The follow-ups are stored only behind their "yes" (`Evening.stored…`), which also
/// keeps the table's `stress_diary_day_effect_needs_action` CHECK satisfied.
struct StressDiaryWrite: Encodable, Sendable, Equatable {
    let patientId: String
    let assessmentId: String
    let localDate: String
    let timezone: String
    let part: StressDiaryPart
    let morning: StressCheckinDraft.Morning
    let evening: StressCheckinDraft.Evening
    /// When the member tapped Save.
    let at: Date
    /// True when no row existed for this date when the screen loaded.
    let isFirstWrite: Bool

    static let via: StressSurface = .ios
    /// For the backend's `on_conflict=` — the unique index `stress_diary_day_natural_key`.
    static let naturalKey = "patient_id,assessment_id,local_date"

    func encode(to encoder: any Encoder) throws {
        typealias Column = StressDiaryDay.CodingKeys
        var c = encoder.container(keyedBy: Column.self)
        try c.encode(patientId, forKey: .patientId)
        try c.encode(assessmentId, forKey: .assessmentId)
        try c.encode(localDate, forKey: .localDate)
        try c.encode(timezone, forKey: .timezone)

        switch part {
        case .morning:
            try c.encodeExplicit(morning.recovered, forKey: .amRecovered)
            try c.encodeExplicit(morning.unwell, forKey: .amUnwell)
            try c.encodeExplicit(morning.alcoholLastEvening, forKey: .alcoholLastEvening)
        case .evening:
            try c.encodeExplicit(evening.peak, forKey: .pmPeak)
            try c.encodeExplicit(evening.recoveryLatency, forKey: .pmRecoveryLatency)
            try c.encodeExplicit(evening.carryover, forKey: .pmCarryover)
            try c.encodeExplicit(evening.storedWorkDetachment, forKey: .pmWorkDetachment)
            try c.encodeExplicit(evening.restorative, forKey: .pmRestorative)
            // NOT NULL default '{}': an empty array, never null.
            try c.encode(evening.storedRestorativeTypes, forKey: .pmRestorativeTypes)
            try c.encodeExplicit(evening.storedRestorativeEffect, forKey: .pmRestorativeEffect)
            try c.encodeExplicit(evening.meaningfulConnection, forKey: .pmMeaningfulConnection)
        }

        try c.encode(Self.via, forKey: .updatedVia)
        if isFirstWrite {
            try c.encode(Self.via, forKey: .loggedVia)
            try c.encode(ISO8601.string(at), forKey: .loggedAt)
        }
    }
}

private extension KeyedEncodingContainer {
    /// `encodeIfPresent` OMITS a nil, which in a merge-duplicates upsert means "leave
    /// the stored value". This writes a JSON `null` instead: "the member left it blank".
    mutating func encodeExplicit<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

// MARK: - pillar_assessment — the read shape

/// The member's active Stress assessment. Member RLS lets them read their own rows.
struct StressAssessmentRow: Decodable, Sendable, Equatable {
    let id: String
    let pillar: String
    let status: String
    let protocolDays: Int
    let startedOn: String
    let plannedEndOn: String?
    /// Read so the window matches the engine's (`stressAssessmentWindow`) exactly.
    let actualEndOn: String?
    let timezoneDefault: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, pillar, status
        case protocolDays = "protocol_days"
        case startedOn = "started_on"
        case plannedEndOn = "planned_end_on"
        case actualEndOn = "actual_end_on"
        case timezoneDefault = "timezone_default"
    }

    static let columns = CodingKeys.allCases.map(\.rawValue).joined(separator: ",")

    /// Filter values for the query: `pillar=eq.stress&status=eq.active`.
    static let stressPillar = "stress"
    static let activeStatus = "active"

    var isActiveStress: Bool { pillar == Self.stressPillar && status == Self.activeStatus }
}

// MARK: - pillar_questionnaire_response — two answer keys, for the S7 gate only

/// Exactly what `StressWorkGate` needs from the member's own L1 answers, and nothing
/// more: the status and two answer keys, pulled out server-side with PostgREST's JSON
/// path select so the rest of the answers never reach the phone.
///
/// This app never reads a GAD-2 / PHQ-2 item from here, never reads
/// `pillar_instrument_result` (it has no member policy — a read returns zero rows,
/// which is "not visible to you", NOT "negative"), and never reads a flag.
struct StressQuestionnaireWorkRow: Decodable, Sendable, Equatable {
    let status: String
    let stressSources: [String]?
    let stressGoal: [String]?

    enum CodingKeys: String, CodingKey {
        case status
        case stressSources = "stress_sources"
        case stressGoal = "stress_goal"
    }

    static let select = "status,stress_sources:answers->stress_sources,stress_goal:answers->stress_goal"

    var isSubmitted: Bool { status == "submitted" }
}
