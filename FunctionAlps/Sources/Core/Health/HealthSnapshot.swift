import Foundation

/// What the phone shows the member from Apple Health: today's readings next to their own last seven days.
/// Pure model + builder — no HealthKit here (`WearableService.readSnapshot` feeds it), so the roll-up is testable.
///
/// Copy rule for every surface that renders this: a line DESCRIBES a reading (steps, a night, a resting pulse)
/// and how it compares to the member's own week. Nothing here judges the body or links a reading to a food.
struct HealthSnapshot: Sendable, Equatable {
    enum Metric: String, Sendable, CaseIterable, Identifiable {
        case steps, distance, activeEnergy, exerciseMinutes, sleep, restingHeartRate, hrv, respiratoryRate, spo2, vo2max, weight
        var id: String { rawValue }
        /// A sum over the day (steps, minutes, a night) vs a reading (a pulse, a weight).
        var isCumulative: Bool {
            switch self {
            case .steps, .distance, .activeEnergy, .exerciseMinutes, .sleep: true
            default: false
            }
        }
        /// The four the Home card leads with.
        static let headline: [Metric] = [.steps, .sleep, .restingHeartRate, .hrv]
        static let activity: [Metric] = [.steps, .distance, .activeEnergy, .exerciseMinutes]
        static let heart: [Metric] = [.restingHeartRate, .hrv, .respiratoryRate, .spo2, .vo2max]
        static let body: [Metric] = [.weight]
    }

    struct Stat: Sendable, Equatable, Identifiable {
        let metric: Metric
        /// Today's value (last night's for sleep); nil when Health holds nothing for today.
        let today: Double?
        /// Mean of the previous seven days that carry a value — today excluded; nil under two such days.
        let weekMean: Double?
        /// The last eight days, oldest first, today last; nil where Health has nothing.
        let series: [Double?]
        var id: Metric { metric }
        /// Today against the member's own week, as a ratio (0.12 = 12 % above). nil without both sides.
        var deltaRatio: Double? {
            guard let t = today, let w = weekMean, w > 0 else { return nil }
            return t / w - 1
        }
        var hasAnything: Bool { today != nil || series.contains { $0 != nil } }
    }

    struct Workout: Sendable, Equatable, Identifiable {
        let name: String
        let minutes: Double
        let kcal: Double?
        var id: String { "\(name)-\(minutes)-\(kcal ?? 0)" }
    }

    let day: String
    let capturedAt: Date
    let stats: [Stat]
    /// Last night's main sleep as Apple Health assembled it (stages, latency, interruptions).
    let night: SleepNight?
    let workoutsToday: [Workout]

    func stat(_ metric: Metric) -> Stat? { stats.first { $0.metric == metric } }
    var hasAnyReading: Bool { stats.contains(where: \.hasAnything) }
    /// The headline metrics that have at least one reading in the window, in card order.
    var headline: [Stat] { Metric.headline.compactMap(stat).filter(\.hasAnything) }

    /// `count` local day keys ending on `now`'s day, oldest first.
    static func dayKeys(ending now: Date, count: Int, calendar: Calendar) -> [String] {
        (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: now).map { ISO8601.day($0, calendar: calendar) }
        }
    }

    /// `values[metric][day]` = the day's reading; `nights` from `SleepAssembler` (keyed by the day the sleep ended).
    static func build(
        days: [String],
        values: [Metric: [String: Double]],
        nights: [SleepNight],
        workoutsToday: [Workout],
        now: Date,
        calendar: Calendar
    ) -> HealthSnapshot {
        let today = days.last ?? ISO8601.day(now, calendar: calendar)
        var all = values
        // Sleep: a night per day, in hours asleep.
        all[.sleep] = Dictionary(nights.map { ($0.day, $0.asleepSeconds / 3600) }, uniquingKeysWith: { _, b in b })
        let stats: [Stat] = Metric.allCases.compactMap { metric in
            let byDay = all[metric] ?? [:]
            let series = days.map { byDay[$0] }
            let previous = series.dropLast().compactMap { $0 }
            let weekMean = previous.count >= 2 ? previous.reduce(0, +) / Double(previous.count) : nil
            let stat = Stat(metric: metric, today: byDay[today], weekMean: weekMean, series: series)
            return stat.hasAnything ? stat : nil
        }
        let night = nights.first { $0.day == today }
        return HealthSnapshot(day: today, capturedAt: now, stats: stats, night: night, workoutsToday: workoutsToday)
    }
}

/// How a reading is written on screen. Pure; the locale is a parameter so the tests pin it.
enum HealthFormat {
    static func value(_ v: Double, metric: HealthSnapshot.Metric, locale: Locale = .current) -> String {
        switch metric {
        case .steps: return integer(v, locale: locale)
        case .distance: return decimal(v / 1000, digits: 1, locale: locale) + " km"
        case .activeEnergy: return integer(v, locale: locale) + " kcal"
        case .exerciseMinutes: return integer(v, locale: locale) + " min"
        case .sleep: return hours(v)
        case .restingHeartRate: return integer(v, locale: locale) + " bpm"
        case .hrv: return integer(v, locale: locale) + " ms"
        case .respiratoryRate: return integer(v, locale: locale) + " /min"
        case .spo2: return integer(v, locale: locale) + " %"
        case .vo2max: return decimal(v, digits: 1, locale: locale)
        case .weight: return decimal(v, digits: 1, locale: locale) + " kg"
        }
    }

    /// "7 h 12" — a night, from hours.
    static func hours(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        return "\(total / 60) h \(String(format: "%02d", total % 60))"
    }

    /// "+12 %" / "−8 %" against the member's own week; "±0 %" inside a point.
    static func delta(_ ratio: Double) -> String {
        let pct = Int((ratio * 100).rounded())
        if abs(pct) < 1 { return "±0 %" }
        return (pct > 0 ? "+" : "−") + "\(abs(pct)) %"
    }

    static func integer(_ v: Double, locale: Locale) -> String {
        let f = NumberFormatter(); f.locale = locale; f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? String(Int(v.rounded()))
    }

    static func decimal(_ v: Double, digits: Int, locale: Locale) -> String {
        let f = NumberFormatter(); f.locale = locale; f.numberStyle = .decimal; f.maximumFractionDigits = digits; f.minimumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(digits)f", v)
    }

    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

extension HealthSnapshot.Metric {
    var label: String {
        switch self {
        case .steps: String(localized: "health.steps", defaultValue: "Steps")
        case .distance: String(localized: "health.distance", defaultValue: "Distance")
        case .activeEnergy: String(localized: "health.activeEnergy", defaultValue: "Active energy")
        case .exerciseMinutes: String(localized: "health.exercise", defaultValue: "Exercise")
        case .sleep: String(localized: "health.sleep", defaultValue: "Sleep")
        case .restingHeartRate: String(localized: "health.restingHR", defaultValue: "Resting heart rate")
        case .hrv: String(localized: "health.hrv", defaultValue: "Heart rate variability")
        case .respiratoryRate: String(localized: "health.respiratory", defaultValue: "Breathing rate")
        case .spo2: String(localized: "health.spo2", defaultValue: "Blood oxygen")
        case .vo2max: String(localized: "health.vo2max", defaultValue: "VO₂ max")
        case .weight: String(localized: "health.weight", defaultValue: "Weight")
        }
    }

    /// Short label for a tile.
    var shortLabel: String {
        switch self {
        case .restingHeartRate: String(localized: "health.restingHR.short", defaultValue: "Resting HR")
        case .hrv: String(localized: "health.hrv.short", defaultValue: "HRV")
        default: label
        }
    }

    var symbol: String {
        switch self {
        case .steps: "figure.walk"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .activeEnergy: "flame"
        case .exerciseMinutes: "figure.run"
        case .sleep: "moon.zzz"
        case .restingHeartRate: "heart"
        case .hrv: "waveform.path.ecg"
        case .respiratoryRate: "lungs"
        case .spo2: "drop"
        case .vo2max: "lungs.fill"
        case .weight: "scalemass"
        }
    }

    /// One descriptive sentence: what Apple measures, never what it means for the body.
    var about: String {
        switch self {
        case .steps: String(localized: "health.about.steps", defaultValue: "Counted by your iPhone and Apple Watch through the day.")
        case .distance: String(localized: "health.about.distance", defaultValue: "Walking and running distance, added up over the day.")
        case .activeEnergy: String(localized: "health.about.activeEnergy", defaultValue: "The energy Apple estimates you burned moving, on top of resting energy.")
        case .exerciseMinutes: String(localized: "health.about.exercise", defaultValue: "Minutes at a brisk-walk effort or more — Apple's exercise ring.")
        case .sleep: String(localized: "health.about.sleep", defaultValue: "Last night's main sleep as Apple recorded it: time asleep, and the stages when a Watch was worn.")
        case .restingHeartRate: String(localized: "health.about.restingHR", defaultValue: "Your pulse during still moments of the day, estimated by the Watch.")
        case .hrv: String(localized: "health.about.hrv", defaultValue: "How much the gap between heartbeats varies (SDNN), sampled by the Watch at rest.")
        case .respiratoryRate: String(localized: "health.about.respiratory", defaultValue: "Breaths per minute, measured during sleep.")
        case .spo2: String(localized: "health.about.spo2", defaultValue: "Blood oxygen saturation, sampled by the Watch.")
        case .vo2max: String(localized: "health.about.vo2max", defaultValue: "Apple's estimate of oxygen use during outdoor walks and runs.")
        case .weight: String(localized: "health.about.weight", defaultValue: "The latest weight written to Health — a connected scale or your own entry.")
        }
    }
}
