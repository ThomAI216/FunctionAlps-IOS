import Foundation

/// Last night as a WEARABLE recorded it, read back from `wearable_daily` — the fallback behind the
/// phone's own HealthKit read, and the only source for a member whose ring or watch syncs server-side
/// (Oura, WHOOP, Polar, Withings, Suunto, Fitbit) rather than through Apple Health on this phone.
///
/// ⚠ THE CLOCK COMES FROM `value` + `timezone_offset`, NEVER FROM `value_text`. The shared writer
/// (`_shared/wearables/core.ts`, `dailyDate`) stores `value = epoch seconds` and overwrites
/// `value_text` with `new Date(t).toISOString()` — always UTC, the vendor's own offset discarded.
/// Rendering `value_text` would show a member in Zurich "21:10" for a 23:10 bedtime.
struct WearableNightRow: Decodable, Sendable, Equatable {
    let day: String
    let dataTypeId: Int
    let dataSourceId: Int
    let value: Double?
    /// Minutes east of UTC, as the vendor recorded the night. Null on rows a source didn't stamp.
    let timezoneOffset: Int?
}

/// One night, in the vocabulary the morning check-in fills in.
struct WearableNight: Sendable, Equatable {
    /// `YYYY-MM-DD` — the local day the night ENDED (the catalogue convention, same as `SleepNight.day`).
    let day: String
    /// `wearable_daily.data_source_id` — names the source in the member-facing line.
    let sourceId: Int
    var bedTime: String?        // "HH:mm", the member's own clock
    var wakeTime: String?       // "HH:mm"
    var durationMin: Int?       // time in bed, to match what the member would read off the two clocks
    var latency: String?        // lt_15 | 15_30 | 30_60 | gt_60
    var wakeCount: String?      // 0 | 1_2 | 3plus
    /// The row carried no `timezone_offset`, so the clock was rendered in the PHONE's zone — right for
    /// a member who slept at home, wrong for one who flew. Withings stamps no offset at all, and the
    /// offset parsers for Polar and Suunto return null for a `…​.000Z` timestamp, so this is not rare.
    /// The member is told, rather than shown a confident wrong time.
    var clockIsGuessed = false

    /// Nothing to prefill from — every field the check-in asks for came back empty.
    var isEmpty: Bool { bedTime == nil && wakeTime == nil && durationMin == nil && latency == nil && wakeCount == nil }
}

extension WearableNight {
    /// The night HealthKit gave this phone — the clock straight from the samples, no round trip.
    init(local night: SleepNight) {
        self.init(
            day: night.day, sourceId: WearableSource.appleHealth,
            bedTime: HealthFormat.clock(night.start), wakeTime: HealthFormat.clock(night.end),
            durationMin: SleepInputsView.windowMinutes(bed: HealthFormat.clock(night.start), wake: HealthFormat.clock(night.end)),
            latency: WearableNightAssembler.latencyBand(seconds: night.latencySeconds),
            wakeCount: WearableNightAssembler.wakeCountBand(Double(night.interruptions))
        )
    }
}

/// Pure: the catalogue rows of one or more days → the newest usable night.
enum WearableNightAssembler {
    /// Main-sleep duration · in-bed · latency · start · end · interruptions.
    static let duration = 2300, inBed = 2301, latency = 2307, start = 2400, end = 2401, interruptions = 2402
    static let typeIds = [duration, inBed, latency, start, end, interruptions]
    static var typeIdList: String { typeIds.map(String.init).joined(separator: ",") }

    /// An epoch instant + the offset it was recorded at → the wall clock the member saw.
    /// No offset on the row → the phone's own zone, which is right for someone who hasn't travelled
    /// and is the only honest guess when the source didn't say.
    static func clock(epochSeconds: Double?, offsetMinutes: Int?, fallback: TimeZone = .current) -> String? {
        guard let epochSeconds, epochSeconds > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = offsetMinutes.flatMap { TimeZone(secondsFromGMT: $0 * 60) } ?? fallback
        let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: epochSeconds))
        guard let h = parts.hour, let m = parts.minute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    /// The same bands the member would tap, from the seconds a wearable reports.
    static func latencyBand(seconds: Double?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let minutes = seconds / 60
        if minutes < 15 { return "lt_15" }
        if minutes < 30 { return "15_30" }
        if minutes < 60 { return "30_60" }
        return "gt_60"
    }

    static func wakeCountBand(_ count: Double?) -> String? {
        guard let count, count >= 0 else { return nil }
        if count == 0 { return "0" }
        return count <= 2 ? "1_2" : "3plus"
    }

    /// The night of `day` (default: the newest present), assembled from ONE source — the one that
    /// carries the most of it, so a ring that records the clock beats a phone that only uploaded a duration.
    static func night(from rows: [WearableNightRow], on day: String? = nil, fallback: TimeZone = .current) -> WearableNight? {
        guard let day = day ?? rows.map(\.day).max() else { return nil }
        let today = rows.filter { $0.day == day }
        guard !today.isEmpty else { return nil }
        let bySource = Dictionary(grouping: today, by: \.dataSourceId)
        let candidates = bySource.map { sourceId, rows -> WearableNight in
            func value(_ typeId: Int) -> WearableNightRow? { rows.first { $0.dataTypeId == typeId } }
            let bed = value(start), wake = value(end)
            let bedTime = clock(epochSeconds: bed?.value, offsetMinutes: bed?.timezoneOffset, fallback: fallback)
            let wakeTime = clock(epochSeconds: wake?.value, offsetMinutes: wake?.timezoneOffset, fallback: fallback)
            // A clock we rendered in the phone's zone because the row didn't say which zone it was.
            let guessed = (bedTime != nil && bed?.timezoneOffset == nil) || (wakeTime != nil && wake?.timezoneOffset == nil)
            // In bed, from the two clocks when they are there (what the member would read), else what
            // the source called time-in-bed, else the asleep duration.
            let window = (bedTime != nil && wakeTime != nil) ? SleepInputsView.windowMinutes(bed: bedTime!, wake: wakeTime!) : nil
            let reported = (value(inBed)?.value ?? value(duration)?.value).map { Int(($0 / 60).rounded()) }
            return WearableNight(
                day: day, sourceId: sourceId,
                bedTime: bedTime, wakeTime: wakeTime,
                durationMin: window ?? reported,
                latency: latencyBand(seconds: value(latency)?.value),
                wakeCount: wakeCountBand(value(interruptions)?.value),
                clockIsGuessed: guessed
            )
        }
        // Richest night wins; the clock counts double — it is the half nothing else can reconstruct.
        func richness(_ n: WearableNight) -> Int {
            var score = 0
            if n.bedTime != nil { score += 2 }
            if n.wakeTime != nil { score += 2 }
            if n.durationMin != nil { score += 1 }
            if n.latency != nil { score += 1 }
            if n.wakeCount != nil { score += 1 }
            return score
        }
        return candidates.filter { !$0.isEmpty }.max { richness($0) < richness($1) || (richness($0) == richness($1) && $0.sourceId > $1.sourceId) }
    }
}
