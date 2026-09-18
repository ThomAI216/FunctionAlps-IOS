import Foundation
import Testing
@testable import FunctionAlps

/// The morning check-in's prefill, read back from `wearable_daily`. The shapes here are the ones the
/// vendor adapters actually write (`supabase/functions/_shared/wearables/*.ts` and their golden tests) —
/// each vendor files a different subset, and the prefill has to survive every one of them.
@Suite("Wearable night — the clock a ring or watch recorded")
struct WearableNightTests {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!

    private func row(_ typeId: Int, _ value: Double, tz: Int? = 120, day: String = "2026-09-13", source: Int = 1_000_018) -> WearableNightRow {
        WearableNightRow(day: day, dataTypeId: typeId, dataSourceId: source, value: value, timezoneOffset: tz)
    }

    // 2026-09-12T23:10:00+02:00 and 2026-09-13T06:40:00+02:00 — the Oura golden fixture.
    private let bedInstant: Double = 1_789_247_400
    private let wakeInstant: Double = 1_789_274_400

    @Test("The clock is the instant read at the offset the night was recorded at, never value_text")
    func clockFromInstantAndOffset() {
        #expect(WearableNightAssembler.clock(epochSeconds: bedInstant, offsetMinutes: 120) == "23:10")
        #expect(WearableNightAssembler.clock(epochSeconds: wakeInstant, offsetMinutes: 120) == "06:40")
        // The same instants in UTC are the "21:10" a member would never recognise — the reason
        // `value_text` (which the shared writer rewrites to UTC) is not read at all.
        #expect(WearableNightAssembler.clock(epochSeconds: bedInstant, offsetMinutes: 0) == "21:10")
        // No offset on the row → the phone's own zone, honestly flagged elsewhere as a guess.
        #expect(WearableNightAssembler.clock(epochSeconds: bedInstant, offsetMinutes: nil, fallback: zurich) == "23:10")
        #expect(WearableNightAssembler.clock(epochSeconds: nil, offsetMinutes: 120) == nil)
        #expect(WearableNightAssembler.clock(epochSeconds: 0, offsetMinutes: 120) == nil)
    }

    @Test("Seconds and counts land in the bands the member would have tapped")
    func bands() {
        #expect(WearableNightAssembler.latencyBand(seconds: 0) == "lt_15")
        #expect(WearableNightAssembler.latencyBand(seconds: 14 * 60) == "lt_15")
        #expect(WearableNightAssembler.latencyBand(seconds: 15 * 60) == "15_30")
        #expect(WearableNightAssembler.latencyBand(seconds: 45 * 60) == "30_60")
        #expect(WearableNightAssembler.latencyBand(seconds: 61 * 60) == "gt_60")
        #expect(WearableNightAssembler.latencyBand(seconds: nil) == nil)
        #expect(WearableNightAssembler.wakeCountBand(0) == "0")
        #expect(WearableNightAssembler.wakeCountBand(2) == "1_2")
        #expect(WearableNightAssembler.wakeCountBand(3) == "3plus")
        #expect(WearableNightAssembler.wakeCountBand(nil) == nil)
    }

    @Test("An Oura night fills every field the morning asks for")
    func ouraNight() throws {
        let rows = [
            row(2400, bedInstant), row(2401, wakeInstant),
            row(2300, 25_200), row(2301, 27_000), row(2307, 12 * 60), row(2402, 1),
        ]
        let night = try #require(WearableNightAssembler.night(from: rows, on: "2026-09-13", fallback: zurich))
        #expect(night.bedTime == "23:10" && night.wakeTime == "06:40")
        #expect(night.durationMin == 450)          // the window between the two clocks, wrapping midnight
        #expect(night.latency == "lt_15")
        #expect(night.wakeCount == "1_2")
        #expect(!night.clockIsGuessed)
        #expect(night.sourceId == 1_000_018)
    }

    @Test("Polar files only the clock — the duration comes from the two times")
    func polarNightHasNoDuration() throws {
        let rows = [row(2400, bedInstant, source: 1_000_003), row(2401, wakeInstant, source: 1_000_003)]
        let night = try #require(WearableNightAssembler.night(from: rows, fallback: zurich))
        #expect(night.durationMin == 450)
        #expect(night.latency == nil && night.wakeCount == nil)   // Polar writes neither; the member says
    }

    @Test("WHOOP has no latency and no wake count — those stay the member's to answer")
    func whoopLeavesGaps() throws {
        let rows = [row(2400, bedInstant, source: 1_000_042), row(2401, wakeInstant, source: 1_000_042), row(2300, 25_200, source: 1_000_042)]
        let night = try #require(WearableNightAssembler.night(from: rows, fallback: zurich))
        #expect(night.bedTime == "23:10")
        #expect(night.latency == nil && night.wakeCount == nil)
    }

    @Test("Suunto can file a wake time with no bedtime; the half-night still prefills")
    func halfANight() throws {
        let rows = [row(2401, wakeInstant, source: 1_000_050), row(2300, 25_200, source: 1_000_050)]
        let night = try #require(WearableNightAssembler.night(from: rows, fallback: zurich))
        #expect(night.bedTime == nil && night.wakeTime == "06:40")
        #expect(night.durationMin == 420)   // no window to measure → the source's own asleep duration
    }

    @Test("Withings stamps no timezone at all: the clock is read here, and says so")
    func withingsHasNoOffset() throws {
        let rows = [row(2400, bedInstant, tz: nil, source: 1_000_008), row(2401, wakeInstant, tz: nil, source: 1_000_008)]
        let night = try #require(WearableNightAssembler.night(from: rows, fallback: zurich))
        #expect(night.bedTime == "23:10" && night.wakeTime == "06:40")
        #expect(night.clockIsGuessed)
    }

    @Test("Two sources on one night: the one that knows when you slept wins")
    func richestSourceWins() throws {
        let rows = [
            // Apple Health relayed a duration and nothing else…
            row(2300, 25_200, source: WearableSource.appleHealth), row(2402, 0, source: WearableSource.appleHealth),
            // …the ring has the clock.
            row(2400, bedInstant, source: 1_000_018), row(2401, wakeInstant, source: 1_000_018),
        ]
        let night = try #require(WearableNightAssembler.night(from: rows, fallback: zurich))
        #expect(night.sourceId == 1_000_018)
        #expect(night.bedTime == "23:10")
    }

    @Test("Only the day asked for; a ring that hasn't synced today prefills nothing")
    func staleNightIsNotOffered() {
        let yesterday = [row(2400, bedInstant, day: "2026-09-12"), row(2401, wakeInstant, day: "2026-09-12")]
        #expect(WearableNightAssembler.night(from: yesterday, on: "2026-09-13", fallback: zurich) == nil)
        // Without a day, the newest present is used (the Home chip's read).
        #expect(WearableNightAssembler.night(from: yesterday, fallback: zurich)?.day == "2026-09-12")
        #expect(WearableNightAssembler.night(from: [], fallback: zurich) == nil)
        // Rows with nothing usable on them are not a night.
        #expect(WearableNightAssembler.night(from: [row(2306, 1_800)], fallback: zurich) == nil)
    }

    @Test("Apple Health on this phone needs no round trip — the samples carry the clock")
    func fromLocalHealthKit() {
        let start = Date(timeIntervalSince1970: bedInstant), end = Date(timeIntervalSince1970: wakeInstant)
        let local = SleepNight(day: "2026-09-13", start: start, end: end, asleepSeconds: 25_200, inBedSeconds: 27_000,
                               remSeconds: 5_400, deepSeconds: 4_200, lightSeconds: 15_600, awakeSeconds: 1_800,
                               latencySeconds: 20 * 60, interruptions: 3)
        let night = WearableNight(local: local)
        #expect(night.sourceId == WearableSource.appleHealth)
        #expect(night.latency == "15_30")
        #expect(night.wakeCount == "3plus")
        #expect(!night.clockIsGuessed)
        #expect(night.durationMin == 450)
    }

    @Test("The phone ships the night's clock too, so the server is not left with a length alone")
    func healthKitUploadsTheClock() {
        let start = Date(timeIntervalSince1970: bedInstant), end = Date(timeIntervalSince1970: wakeInstant)
        let local = SleepNight(day: "2026-09-13", start: start, end: end, asleepSeconds: 25_200, inBedSeconds: 27_000,
                               remSeconds: 0, deepSeconds: 0, lightSeconds: 0, awakeSeconds: 900,
                               latencySeconds: 300, interruptions: 1)
        let rows = SleepAssembler.rows(for: local, timezoneOffset: 120)
        let start2400 = rows.first { $0.dataTypeId == 2400 }
        let end2401 = rows.first { $0.dataTypeId == 2401 }
        #expect(start2400?.value == bedInstant)          // whole epoch seconds, as `dailyDate` writes them
        #expect(end2401?.value == wakeInstant)
        #expect(start2400?.valueType == "DATE")
        #expect(start2400?.timezoneOffset == 120)
        // And what it writes reads back through the same assembler.
        let rebuilt = WearableNightAssembler.night(from: rows.compactMap { r in
            r.value.map { WearableNightRow(day: r.day, dataTypeId: r.dataTypeId, dataSourceId: r.dataSourceId, value: $0, timezoneOffset: r.timezoneOffset) }
        }, fallback: zurich)
        #expect(rebuilt?.bedTime == "23:10" && rebuilt?.wakeTime == "06:40")
    }
}
