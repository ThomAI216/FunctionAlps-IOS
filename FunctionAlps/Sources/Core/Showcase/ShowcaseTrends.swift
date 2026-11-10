#if DEBUG
import Foundation

/// The Trends rework's sample data (owner-validated mockup v2): 35 days of check-ins shaped so the page shows its
/// range — energy and mood steady, focus on the rise, stress and digestion dipped the last days — an Oura ring
/// (nights, readings, a live account), meal reactions, symptoms and Bristol types, and two validated patterns.
/// Deterministic: every value is a function of the day offset, so the screenshots reproduce.
extension ShowcaseData {
    static let trendsDeviceKey = "oura"
    static let trendsDays = 35

    private static func wave(_ ago: Int, _ freq: Double, _ phase: Double, _ amp: Double) -> Double { amp * sin(Double(ago) * freq + phase) }

    // MARK: The markers, 0–100 (stress as CALM — the marker contract)

    static func trendEnergy(_ ago: Int) -> Int { Int((62 + wave(ago, 0.9, 0.3, 6)).rounded()) }
    static func trendMood(_ ago: Int) -> Int { Int((70 + wave(ago, 1.1, 1.0, 5)).rounded()) }
    static func trendSleep(_ ago: Int) -> Int { Int((66 + wave(ago, 0.8, 2.0, 5) + (ago < 4 ? 6 : 0)).rounded()) }
    static func trendFocus(_ ago: Int) -> Int { Int((54 + wave(ago, 1.3, 0.5, 3) + Double(max(0, 5 - ago)) * 5).rounded()) }
    static func trendCalm(_ ago: Int) -> Int { Int((58 + wave(ago, 1.0, 2.7, 5) - (ago < 3 ? 22 : 0)).rounded()) }
    static func trendGut(_ ago: Int) -> Int { Int((64 + wave(ago, 0.8, 0.8, 6) - (ago == 1 || ago == 2 ? 22 : 0)).rounded()) }

    /// 35 days; today always in (the Trends page reads today).
    static func trendCheckins() -> [DailyCheckin] {
        (0..<trendsDays).reversed().map { ago in
            DailyCheckin(
                day: day(-ago), functionalCompletedAt: at(-ago, 20, 40), gutCompletedAt: at(-ago, 20, 42),
                energy: trendEnergy(ago), mood: trendMood(ago), sleep: trendSleep(ago), calmness: trendCalm(ago), gutOverall: trendGut(ago)
            )
        }
    }

    // MARK: Moments — focus, the night as the member wrote it, and the pills

    private static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func trendMoments() -> [String: [CheckinMoment]] {
        var out: [String: [CheckinMoment]] = [:]
        for ago in 0..<trendsDays {
            var m = CheckinMoment(slot: .evening, submittedAt: at(-ago, 20, 40))
            m.energyBody = trendEnergy(ago); m.energyMind = trendFocus(ago); m.energyOverall = trendEnergy(ago)
            m.moodScore = trendMood(ago); m.stressScore = trendCalm(ago); m.sleepOverall = trendSleep(ago)
            m.sleepRefreshed = min(100, max(0, trendSleep(ago) - 4 + (ago % 3) * 2))
            let bed = 22 * 60 + 50 + (ago * 13) % 50
            let wake = 6 * 60 + 40 + (ago * 7) % 25
            m.sleepBedTime = clock(bed); m.sleepWakeTime = clock(wake)
            m.sleepDurationMin = SleepSpecials.windowMinutes(bed: clock(bed), wake: clock(wake))
            m.sleepWakeCount = ago % 3 == 0 ? "1_2" : "0"
            var pills: [String: [String]] = [:]
            if ago % 3 == 0 {
                pills["drained"] = ["short_night", "skipped_meal"]
            } else {
                pills["fuelled"] = ["proper_meal", "walk_outside"]
            }
            pills["flavour_pos"] = ["motivated"]
            pills["drivers"] = ago % 2 == 0 ? ["sleep"] : ["food"]
            pills["source"] = ago < 3 ? ["work", "overcommitted"] : ["work"]
            pills["helped"] = ["walk"]
            if ago % 4 == 1 { pills["kept_up"] = ["screen"] }
            m.pills = pills
            out[day(-ago)] = [m]
        }
        return out
    }

    // MARK: Digestion

    static func trendGutDays() -> [GutDay] {
        (0..<trendsDays).reversed().map { ago in
            let overall = trendGut(ago)
            let symptoms: [String] = overall < 45 ? ["bloating", "gas", "cramping"] : overall < 55 ? ["bloating", "gas"] : []
            return GutDay(
                day: day(-ago), comfort: max(0, min(100, overall + (ago % 2 == 0 ? 2 : -3))), stool: curve(ago, from: 60, to: 76, phase: 1.4),
                reactions: curve(ago, from: 58, to: 78, phase: 2.2), overall: overall, stoolQuality: 4, stoolFrequency: ago % 3 == 0 ? 2 : 1,
                completedAt: at(-ago, 20, 42), bristol: [4, 4, 5, 3, 4, 6, 4][ago % 7], symptoms: symptoms
            )
        }
    }

    /// What the member noted about some of their meals (words, not scores). Not every meal has one.
    static func trendMealReactions() -> [String: MealReaction] {
        var out: [String: MealReaction] = [:]
        for ago in 0...20 {
            if ago % 3 != 2 { out["showcase-meal-breakfast-\(ago)"] = MealReaction(overall: 8, flags: ago % 2 == 0 ? ["felt_full"] : []) }
            switch ago % 3 {
            case 0: out["showcase-meal-lunch-\(ago)"] = MealReaction(overall: 5, flags: ["bloating"], bloating: 6)
            case 1: out["showcase-meal-lunch-\(ago)"] = MealReaction(overall: 8, flags: [])
            default: break
            }
            if ago % 4 == 1 { out["showcase-meal-dinner-\(ago)"] = MealReaction(overall: 5, flags: ["heavy"], fullness: 6) }
            else if ago % 2 == 0 { out["showcase-meal-dinner-\(ago)"] = MealReaction(overall: 8, flags: []) }
        }
        return out
    }

    // MARK: Oura

    /// One night as the ring filed it, in the catalogue's rows (`wearable_daily`): the clock, asleep, in bed, latency, wake-ups.
    private static func ouraRows(day: String, wakeMinute: Int, inBedMin: Int, asleepMin: Int, latencyMin: Int, wakes: Int) -> [WearableNightRow] {
        let tz = 60
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: tz * 60) ?? .current
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let wake = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: wakeMinute / 60, minute: wakeMinute % 60)) else { return [] }
        let bed = wake.addingTimeInterval(-Double(inBedMin) * 60)
        func row(_ type: Int, _ value: Double) -> WearableNightRow {
            WearableNightRow(day: day, dataTypeId: type, dataSourceId: 1_000_018, value: value, timezoneOffset: tz)
        }
        return [
            row(WearableNightAssembler.start, bed.timeIntervalSince1970), row(WearableNightAssembler.end, wake.timeIntervalSince1970),
            row(WearableNightAssembler.duration, Double(asleepMin) * 60), row(WearableNightAssembler.inBed, Double(inBedMin) * 60),
            row(WearableNightAssembler.latency, Double(latencyMin) * 60), row(WearableNightAssembler.interruptions, Double(wakes)),
        ]
    }

    static func trendAsleepMin(_ ago: Int) -> Int { 405 + Int((28 * sin(Double(ago) * 0.7)).rounded()) + (ago < 5 ? 12 : 0) }

    static func ouraNights(since: String) -> [WearableNightRow] {
        (0..<trendsDays).flatMap { ago -> [WearableNightRow] in
            let asleep = trendAsleepMin(ago)
            return ouraRows(day: day(-ago), wakeMinute: 6 * 60 + 40 + (ago * 7) % 25, inBedMin: asleep + 28 + (ago % 4) * 3,
                            asleepMin: asleep, latencyMin: 8 + (ago % 5) * 3, wakes: ago % 3 == 0 ? 2 : 1)
        }.filter { $0.day >= since }
    }

    /// The ring's daily readings (`wearable_daily_labeled`): asleep (seconds), resting heart rate, HRV, steps.
    static func ouraDaily(since: String) -> [WearableLabeledRow] {
        (0..<trendsDays).flatMap { ago -> [WearableLabeledRow] in
            let d = day(-ago)
            func row(_ metric: String, _ value: Double) -> WearableLabeledRow {
                WearableLabeledRow(day: d, metric: metric, value: value, dataSourceId: 1_000_018, layer: "raw")
            }
            return [
                row("ThryveMainSleepDuration", Double(trendAsleepMin(ago)) * 60),
                row("HeartRateResting", (54 + wave(ago, 0.9, 0.4, 2)).rounded()),
                row("Rmssd", (50 + wave(ago, 1.2, 1.1, 5)).rounded()),
                row("Steps", (7800 + wave(ago, 0.6, 0.2, 2600)).rounded()),
            ]
        }.filter { $0.day >= since }
    }

    static func ouraAccounts() -> [WearableVendorAccountRow] {
        [WearableVendorAccountRow(vendor: trendsDeviceKey, status: "connected", reconnectRequired: false,
                                  lastSuccessfulSyncAt: at(0, 7, 12), lastErrorCode: nil, connectedAt: at(-30, 9))]
    }

    // MARK: Patterns the practitioner reviewed and shared

    static func sharedPatterns() -> [UserPattern] {
        [
            UserPattern(kind: "pattern", subject: "late_dinner", reaction: "next_energy", direction: "worse", effect: -8, nObs: 5,
                        consistency: 0.8, tier: "confirmed", reviewedAt: at(-2, 9, 30)),
            UserPattern(kind: "trigger_food", subject: "raw vegetables", reaction: "bloating", direction: "worse", effect: nil, nObs: 4,
                        consistency: 0.75, tier: "hint", reviewedAt: at(-2, 9, 31)),
        ]
    }
}
#endif
