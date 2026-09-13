import Foundation
import Testing
@testable import FunctionAlps

@Suite("HealthSnapshot")
struct HealthSnapshotTests {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private let now = Date(timeIntervalSince1970: 1_789_300_000) // 2026-09-13 ~11:46 UTC

    @Test func dayKeysEndToday() {
        let keys = HealthSnapshot.dayKeys(ending: now, count: 8, calendar: utc)
        #expect(keys.count == 8 && keys.first == "2026-09-06" && keys.last == "2026-09-13")
    }

    @Test func todayNextToTheWeekAndTheNightFromSleep() throws {
        let days = HealthSnapshot.dayKeys(ending: now, count: 8, calendar: utc)
        let steps: [String: Double] = ["2026-09-13": 9_000, "2026-09-12": 8_000, "2026-09-11": 6_000, "2026-09-07": 10_000]
        let hr: [String: Double] = ["2026-09-13": 58] // one prior day would not make a week
        let night = SleepNight(day: "2026-09-13", start: now.addingTimeInterval(-12 * 3600), end: now.addingTimeInterval(-4 * 3600),
                               asleepSeconds: 7.5 * 3600, inBedSeconds: 8 * 3600, remSeconds: 0, deepSeconds: 0, lightSeconds: 0, awakeSeconds: 0, latencySeconds: 600, interruptions: 1)
        let old = SleepNight(day: "2026-09-12", start: now, end: now, asleepSeconds: 6 * 3600, inBedSeconds: 6 * 3600, remSeconds: 0, deepSeconds: 0, lightSeconds: 0, awakeSeconds: 0, latencySeconds: 0, interruptions: 0)
        let snap = HealthSnapshot.build(days: days, values: [.steps: steps, .restingHeartRate: hr], nights: [old, night], workoutsToday: [], now: now, calendar: utc)

        let s = try #require(snap.stat(.steps))
        #expect(s.today == 9_000)
        #expect(s.weekMean == 8_000)                          // (8000 + 6000 + 10000) / 3 — today excluded
        #expect(s.series.count == 8 && s.series[1] == 10_000 && s.series[2] == nil && s.series[7] == 9_000)
        #expect(abs((s.deltaRatio ?? 0) - 0.125) < 0.0001)

        #expect(snap.stat(.restingHeartRate)?.weekMean == nil) // under two prior days → no week to compare
        #expect(snap.stat(.sleep)?.today == 7.5)
        #expect(snap.stat(.sleep)?.weekMean == 6)
        #expect(snap.night == night)
        #expect(snap.stat(.weight) == nil)                    // nothing in the window → dropped
        #expect(snap.headline.map(\.metric) == [.steps, .sleep, .restingHeartRate])
        #expect(snap.hasAnyReading)
    }

    @Test func nothingReadIsAnEmptySnapshot() {
        let snap = HealthSnapshot.build(days: HealthSnapshot.dayKeys(ending: now, count: 8, calendar: utc), values: [:], nights: [], workoutsToday: [], now: now, calendar: utc)
        #expect(!snap.hasAnyReading && snap.headline.isEmpty && snap.night == nil)
    }

    @Test func readingsAreWrittenLikeAppleDoes() {
        let en = Locale(identifier: "en_US")
        #expect(HealthFormat.value(8_432, metric: .steps, locale: en) == "8,432")
        #expect(HealthFormat.value(1_234, metric: .distance, locale: en) == "1.2 km")
        #expect(HealthFormat.value(58.4, metric: .restingHeartRate, locale: en) == "58 bpm")
        #expect(HealthFormat.value(7.2, metric: .sleep, locale: en) == "7 h 12")
        #expect(HealthFormat.hours(0.05) == "0 h 03")
        #expect(HealthFormat.delta(0.124) == "+12 %")
        #expect(HealthFormat.delta(-0.08) == "−8 %")
        #expect(HealthFormat.delta(0.004) == "±0 %")
    }
}
