import Foundation

// Apple Health → CM OS wearable catalogue. One place knows both vocabularies.
//
// The edge function `wearable-ingest` stores what the phone sends verbatim (`wearable_raw_events`),
// then upserts `wearable_daily` / `wearable_epoch` on their natural keys. It defaults native rows to
// `data_source_id = 1000001` (the "apple_health_native" sentinel) and `data_type_id = 0`, but accepts
// overrides — and the scoring engine only reads rows whose `data_type_id` labels into the catalogue
// (`wearable_daily_labeled` joins `wearable_data_types`; unlabelled rows have no `layer` and are
// skipped). So the phone sends the CATALOGUE ids for the metrics that already exist there
// (Steps 1000, HeartRateResting 3001, ThryveMainSleepDuration 2300…), and native-only names with
// id 0 for the rest. Same units as the catalogue: sleep durations in SECONDS, activity minutes,
// distance metres, energy kcal, HRV milliseconds.

/// The sentinel source id for Apple Health on this phone (never a Thryve id).
enum WearableSource {
    static let appleHealth = 1_000_001
    static let appleHealthName = "apple_health"
}

/// A catalogued (or native-only) metric the phone can produce.
struct WearableMetric: Sendable, Equatable, Hashable {
    /// `wearable_data_types.data_type_id`; 0 = native-only (labelled by name alone, not scored).
    let typeId: Int
    /// `wearable_data_types.name` (or the native name when `typeId == 0`).
    let name: String
    /// LONG | DOUBLE — what the catalogue declares for the metric.
    let valueType: String

    // Activity (raw layer)
    static let steps = WearableMetric(typeId: 1000, name: "Steps", valueType: "LONG")
    static let distance = WearableMetric(typeId: 1001, name: "CoveredDistance", valueType: "DOUBLE")
    static let burnedCalories = WearableMetric(typeId: 1010, name: "BurnedCalories", valueType: "LONG")
    static let activeCalories = WearableMetric(typeId: 1011, name: "ActiveBurnedCalories", valueType: "LONG")
    static let activityDuration = WearableMetric(typeId: 1100, name: "ActivityDuration", valueType: "LONG")
    // Sleep (analytics layer — the "main sleep" the engine reads; durations in seconds)
    static let sleepDuration = WearableMetric(typeId: 2300, name: "ThryveMainSleepDuration", valueType: "LONG")
    static let sleepInBed = WearableMetric(typeId: 2301, name: "ThryveMainSleepInBedDuration", valueType: "LONG")
    static let sleepREM = WearableMetric(typeId: 2302, name: "ThryveMainSleepREMDuration", valueType: "LONG")
    static let sleepDeep = WearableMetric(typeId: 2303, name: "ThryveMainSleepDeepDuration", valueType: "LONG")
    static let sleepLight = WearableMetric(typeId: 2305, name: "ThryveMainSleepLightDuration", valueType: "LONG")
    static let sleepAwake = WearableMetric(typeId: 2306, name: "ThryveMainSleepAwakeDuration", valueType: "LONG")
    static let sleepLatency = WearableMetric(typeId: 2307, name: "ThryveMainSleepLatency", valueType: "LONG")
    static let sleepInterruptions = WearableMetric(typeId: 2402, name: "ThryveMainSleepInterruptions", valueType: "LONG")
    static let sleepEfficiency = WearableMetric(typeId: 2200, name: "SleepEfficiency", valueType: "LONG")
    // Heart (raw layer)
    static let heartRate = WearableMetric(typeId: 3000, name: "HeartRate", valueType: "LONG")
    static let restingHeartRate = WearableMetric(typeId: 3001, name: "HeartRateResting", valueType: "LONG")
    static let spo2 = WearableMetric(typeId: 3009, name: "SPO2", valueType: "DOUBLE")
    static let vo2max = WearableMetric(typeId: 3030, name: "VO2max", valueType: "DOUBLE")
    /// Apple's HRV is SDNN, not RMSSD — labelled honestly as SDNN (3112). The engine's recovery factor
    /// reads `Rmssd`/`RmssdSleep`; converting SDNN → RMSSD is a modelling decision for the owner.
    static let hrvSDNN = WearableMetric(typeId: 3112, name: "SDNN", valueType: "DOUBLE")
    static let respirationRate = WearableMetric(typeId: 4000, name: "RespirationRate", valueType: "LONG")
    static let weight = WearableMetric(typeId: 5020, name: "Weight", valueType: "DOUBLE")
    // Native-only (id 0): kept by name for the dashboard, not scored
    static let exerciseMinutes = WearableMetric(typeId: 0, name: "apple_exercise_minutes", valueType: "LONG")
    static let standHours = WearableMetric(typeId: 0, name: "apple_stand_hours", valueType: "LONG")
    static let workout = WearableMetric(typeId: 0, name: "workout", valueType: "LONG")
}

/// One `wearable_daily` row as the ingest function expects it (snake_case on the wire).
struct WearableDailyRow: Encodable, Sendable, Equatable {
    let day: String                 // YYYY-MM-DD, the member's local day
    let dataTypeName: String
    let dataTypeId: Int
    let dataSourceId: Int
    let value: Double?
    let valueText: String?
    let valueType: String?
    let timezoneOffset: Int?        // minutes east of UTC
    let details: [String: Double]?
    let recordedAt: String?         // ISO 8601

    init(day: String, metric: WearableMetric, value: Double, timezoneOffset: Int, details: [String: Double]? = nil, recordedAt: Date? = nil) {
        self.day = day
        self.dataTypeName = metric.name
        self.dataTypeId = metric.typeId
        self.dataSourceId = WearableSource.appleHealth
        self.value = metric.valueType == "LONG" ? value.rounded() : (value * 100).rounded() / 100
        self.valueText = nil
        self.valueType = metric.valueType
        self.timezoneOffset = timezoneOffset
        self.details = details
        self.recordedAt = recordedAt.map { ISO8601.string($0) }
    }
}

/// One `wearable_epoch` row (a timed sample — workouts, sleep sessions).
struct WearableEpochRow: Encodable, Sendable, Equatable {
    let startTs: String
    let endTs: String?
    let dataTypeName: String
    let dataTypeId: Int
    let dataSourceId: Int
    let value: Double?
    let valueText: String?
    let valueType: String?
    let timezoneOffset: Int?
    let details: [String: Double]?

    init(start: Date, end: Date?, metric: WearableMetric, value: Double?, valueText: String? = nil, timezoneOffset: Int, details: [String: Double]? = nil) {
        self.startTs = ISO8601.string(start)
        self.endTs = end.map { ISO8601.string($0) }
        self.dataTypeName = metric.name
        self.dataTypeId = metric.typeId
        self.dataSourceId = WearableSource.appleHealth
        self.value = value
        self.valueText = valueText
        self.valueType = metric.valueType
        self.timezoneOffset = timezoneOffset
        self.details = details
    }
}

/// What one sync sends: the daily rows and the timed rows, batched.
struct WearableBatch: Encodable, Sendable, Equatable {
    var daily: [WearableDailyRow] = []
    var epoch: [WearableEpochRow] = []
    var isEmpty: Bool { daily.isEmpty && epoch.isEmpty }
    var count: Int { daily.count + epoch.count }
}

/// `wearable-ingest`'s answer.
struct WearableIngestResult: Decodable, Sendable, Equatable {
    let ok: Bool?
    let rawEventId: String?
    let daily: Int?
    let epoch: Int?
}

/// One `wearable_daily_labeled` row read back (the member's own rows, any source).
struct WearableLabeledRow: Decodable, Sendable, Equatable {
    let day: String
    let metric: String
    let value: Double?
    let dataSourceId: Int
    let layer: String?
}

/// One `wearable_connections` row (Thryve-linked devices connected on the web app).
struct WearableConnectionRow: Decodable, Sendable, Equatable {
    let dataSourceId: Int
    let dataSourceName: String?
    let status: String?
    let connectedAt: Date?
}

// MARK: - Sleep sessions from HealthKit category samples

/// One sleep sample as HealthKit reports it (already mapped off `HKCategoryValueSleepAnalysis`).
struct SleepSample: Sendable, Equatable {
    enum Stage: Sendable, Equatable { case inBed, awake, asleepUnspecified, core, deep, rem }
    let start: Date
    let end: Date
    let stage: Stage
    var seconds: Double { end.timeIntervalSince(start) }
    var isAsleep: Bool { stage == .core || stage == .deep || stage == .rem || stage == .asleepUnspecified }
}

/// The main sleep of one night, in the catalogue's units (seconds, counts).
struct SleepNight: Sendable, Equatable {
    /// The day the night belongs to = the local day the sleep ENDED (the Thryve convention).
    let day: String
    let start: Date
    let end: Date
    let asleepSeconds: Double
    let inBedSeconds: Double
    let remSeconds: Double
    let deepSeconds: Double
    let lightSeconds: Double
    let awakeSeconds: Double
    /// Time from the first in-bed/awake sample to the first asleep sample.
    let latencySeconds: Double
    /// Awake samples that occur between two sleep samples (what the Watch records).
    let interruptions: Int
    var efficiencyPct: Int? { inBedSeconds > 0 ? min(100, Int((100 * asleepSeconds / inBedSeconds).rounded())) : nil }
}

/// Pure: groups sleep samples into nights and reduces each to the catalogue's main-sleep metrics.
enum SleepAssembler {
    /// A gap longer than this between samples starts a new session (a nap after a night, or the next night).
    static let sessionGap: TimeInterval = 3 * 3600
    /// Sessions shorter than this are naps, not the main sleep.
    static let mainSleepMinimum: TimeInterval = 3 * 3600

    static func nights(from samples: [SleepSample], calendar: Calendar = .current) -> [SleepNight] {
        let sorted = samples.sorted { $0.start < $1.start }
        var sessions: [[SleepSample]] = []
        for s in sorted {
            if let last = sessions.last?.last, s.start.timeIntervalSince(last.end) <= sessionGap {
                sessions[sessions.count - 1].append(s)
            } else {
                sessions.append([s])
            }
        }
        var byDay: [String: SleepNight] = [:]
        for session in sessions {
            guard let night = reduce(session, calendar: calendar) else { continue }
            // One main sleep per day: the longest session wins (the night, not the siesta).
            if let existing = byDay[night.day], existing.asleepSeconds >= night.asleepSeconds { continue }
            byDay[night.day] = night
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    private static func reduce(_ session: [SleepSample], calendar: Calendar) -> SleepNight? {
        guard let first = session.first, let last = session.max(by: { $0.end < $1.end }) else { return nil }
        let asleep = session.filter(\.isAsleep)
        let asleepSeconds = asleep.reduce(0) { $0 + $1.seconds }
        guard asleepSeconds >= mainSleepMinimum || session.contains(where: { $0.stage == .inBed && $0.seconds >= mainSleepMinimum }) else { return nil }
        let inBedExplicit = session.filter { $0.stage == .inBed }.reduce(0) { $0 + $1.seconds }
        // Without explicit in-bed samples (Watch nights), in-bed = the span of the session.
        let inBedSeconds = inBedExplicit > 0 ? inBedExplicit : last.end.timeIntervalSince(first.start)
        let rem = session.filter { $0.stage == .rem }.reduce(0) { $0 + $1.seconds }
        let deep = session.filter { $0.stage == .deep }.reduce(0) { $0 + $1.seconds }
        let light = session.filter { $0.stage == .core }.reduce(0) { $0 + $1.seconds }
        let awakeSamples = session.filter { $0.stage == .awake }
        let awake = awakeSamples.reduce(0) { $0 + $1.seconds }
        let firstAsleep = asleep.map(\.start).min() ?? first.start
        let latency = max(0, firstAsleep.timeIntervalSince(first.start))
        // Interruptions: awake samples strictly between two asleep samples.
        let firstAsleepStart = asleep.map(\.start).min() ?? first.start
        let lastAsleepEnd = asleep.map(\.end).max() ?? last.end
        let interruptions = awakeSamples.filter { $0.start >= firstAsleepStart && $0.end <= lastAsleepEnd }.count
        let day = ISO8601.day(last.end, calendar: calendar)
        return SleepNight(
            day: day, start: first.start, end: last.end,
            asleepSeconds: asleepSeconds, inBedSeconds: max(inBedSeconds, asleepSeconds),
            remSeconds: rem, deepSeconds: deep, lightSeconds: light, awakeSeconds: awake,
            latencySeconds: latency, interruptions: interruptions
        )
    }

    /// The catalogue rows for one night.
    static func rows(for night: SleepNight, timezoneOffset: Int) -> [WearableDailyRow] {
        var out: [WearableDailyRow] = [
            WearableDailyRow(day: night.day, metric: .sleepDuration, value: night.asleepSeconds, timezoneOffset: timezoneOffset, recordedAt: night.end),
            WearableDailyRow(day: night.day, metric: .sleepInBed, value: night.inBedSeconds, timezoneOffset: timezoneOffset, recordedAt: night.end),
            WearableDailyRow(day: night.day, metric: .sleepAwake, value: night.awakeSeconds, timezoneOffset: timezoneOffset, recordedAt: night.end),
            WearableDailyRow(day: night.day, metric: .sleepLatency, value: night.latencySeconds, timezoneOffset: timezoneOffset, recordedAt: night.end),
            WearableDailyRow(day: night.day, metric: .sleepInterruptions, value: Double(night.interruptions), timezoneOffset: timezoneOffset, recordedAt: night.end),
        ]
        if night.remSeconds > 0 { out.append(WearableDailyRow(day: night.day, metric: .sleepREM, value: night.remSeconds, timezoneOffset: timezoneOffset, recordedAt: night.end)) }
        if night.deepSeconds > 0 { out.append(WearableDailyRow(day: night.day, metric: .sleepDeep, value: night.deepSeconds, timezoneOffset: timezoneOffset, recordedAt: night.end)) }
        if night.lightSeconds > 0 { out.append(WearableDailyRow(day: night.day, metric: .sleepLight, value: night.lightSeconds, timezoneOffset: timezoneOffset, recordedAt: night.end)) }
        if let eff = night.efficiencyPct { out.append(WearableDailyRow(day: night.day, metric: .sleepEfficiency, value: Double(eff), timezoneOffset: timezoneOffset, recordedAt: night.end)) }
        return out
    }
}

// MARK: - Read-back (the Expo `aggregateWearableRows`, for the wearables screen)

/// One day as the engine sees it: sleep · recovery · activity, collapsed across sources
/// (MAX for cumulative metrics, MEDIAN for point-in-time ones).
struct WearableDay: Sendable, Equatable, Identifiable {
    let date: String
    var sleepHours: Double?
    var sleepEfficiencyPct: Int?
    var restingHr: Int?
    var hrvMs: Double?
    var steps: Int?
    var activeMinutes: Int?
    var activeEnergyKcal: Int?
    var respirationRate: Int?
    var sources: Set<Int>
    var id: String { date }
}

enum WearableAggregation {
    static func days(from rows: [WearableLabeledRow]) -> [WearableDay] {
        var byDay: [String: [String: [Double]]] = [:]
        var sources: [String: Set<Int>] = [:]
        for r in rows {
            guard let v = r.value, r.layer == "raw" || r.layer == "analytics" else { continue }
            byDay[r.day, default: [:]][r.metric, default: []].append(v)
            sources[r.day, default: []].insert(r.dataSourceId)
        }
        func median(_ xs: [Double]) -> Double {
            let s = xs.sorted(); let n = s.count
            return n % 2 == 1 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
        }
        return byDay.keys.sorted().map { day in
            let m = byDay[day] ?? [:]
            func maxOf(_ names: String...) -> Double? { let v = names.flatMap { m[$0] ?? [] }; return v.isEmpty ? nil : v.max() }
            func medOf(_ names: String...) -> Double? { let v = names.flatMap { m[$0] ?? [] }; return v.isEmpty ? nil : median(v) }
            let sleepDur = maxOf("ThryveMainSleepDuration")
            let inBed = maxOf("ThryveMainSleepInBedDuration")
            let hrv = medOf("RmssdSleep") ?? medOf("Rmssd") ?? medOf("SDNN")
            return WearableDay(
                date: day,
                sleepHours: sleepDur.map { ($0 / 360).rounded() / 10 },
                sleepEfficiencyPct: (sleepDur != nil && (inBed ?? 0) > 0) ? min(100, Int((100 * sleepDur! / inBed!).rounded())) : nil,
                restingHr: medOf("HeartRateResting").map { Int($0.rounded()) },
                hrvMs: hrv.map { ($0 * 10).rounded() / 10 },
                steps: maxOf("Steps", "StepsManual").map { Int($0) },
                activeMinutes: maxOf("ActiveDurationManual", "ActivityDuration").map { Int($0) },
                activeEnergyKcal: maxOf("ActiveBurnedCalories").map { Int($0) },
                respirationRate: medOf("RespirationRate").map { Int($0.rounded()) },
                sources: sources[day] ?? []
            )
        }
    }
}

extension ISO8601 {
    /// `YYYY-MM-DD` in the given calendar's time zone.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
