import SwiftUI

/// What a signal's row (and its detail page) says, worded for the member: the headline, the curve, the labels
/// under it, the "avg · previous" line. Counting and formatting only.
struct TrendRowFacts {
    /// "7 h 02" · "6"
    let big: String
    /// "asleep" · "in bed" · "/10"
    let unit: String
    /// "23:05 → 06:50" — Sleep only.
    let sub: String?
    /// The curve, on the scale the member reads (hours for a night, 0–10 for the rest).
    let plotted: [Double?]
    /// One label per window day, for the strip under the expanded curve.
    let labels: [String?]
    let averageLine: String
    /// "from Oura · updated 07:12" — Sleep only.
    let badge: String?
    /// The headline is a night's hours (a device or the check-in's clock), not a 0–10 read.
    let isNight: Bool
}

extension TrendsEngine.Page {
    func facts(_ signal: TrendSignal) -> TrendRowFacts {
        if signal == .sleep, sleep.hasNights, let latest = sleep.latest, let minutes = latest.minutes {
            let hours = sleep.hours
            return TrendRowFacts(
                big: TrendsFormat.hours(minutes: minutes),
                unit: latest.fromDevice
                    ? String(localized: "trends.sleep.asleep", defaultValue: "asleep")
                    : String(localized: "trends.sleep.inBed", defaultValue: "in bed"),
                sub: latest.bedTime != nil && latest.wakeTime != nil ? TrendsFormat.bedToWake(bed: latest.bedTime, wake: latest.wakeTime) : nil,
                plotted: hours,
                labels: hours.map { $0.map { TrendsFormat.oneDecimal($0) } },
                averageLine: TrendsFormat.averageLine(
                    average: sleep.averageHours.map { TrendsFormat.hours($0) },
                    previous: sleep.previousAverageHours.map { TrendsFormat.hours($0) }, days: window.days),
                badge: sleepBadge(latest),
                isNight: true
            )
        }
        let s = series(signal)
        let levels = s?.levels ?? []
        let latestIsToday = s?.latestDay == today
        return TrendRowFacts(
            big: s?.latestLevel.map { TrendsFormat.whole($0) } ?? "·",
            unit: latestIsToday
                ? String(localized: "trends.unit.outOfTenToday", defaultValue: "/10 today")
                : String(localized: "trends.unit.outOfTen", defaultValue: "/10"),
            sub: nil,
            plotted: levels,
            labels: levels.map { $0.map { TrendsFormat.whole($0) } },
            averageLine: TrendsFormat.averageLine(
                average: s?.averageLevel.map { TrendsFormat.oneDecimal($0) },
                previous: s?.previousAverageLevel.map { TrendsFormat.oneDecimal($0) }, days: window.days),
            badge: nil,
            isNight: false
        )
    }

    /// "from Oura · updated 07:12"; "from check-in" when no device filed the night.
    private func sleepBadge(_ latest: TrendsEngine.SleepEntry) -> String {
        guard latest.fromDevice else { return String(localized: "trends.sleep.fromCheckin", defaultValue: "from check-in") }
        guard let updated = sleep.updatedAt else { return String(localized: "trends.sleep.from", defaultValue: "from \(latest.source)") }
        return String(localized: "trends.sleep.fromUpdated", defaultValue: "from \(latest.source) · updated \(HealthFormat.clock(updated))")
    }
}
