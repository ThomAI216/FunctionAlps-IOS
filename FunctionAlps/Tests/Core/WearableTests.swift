import Foundation
import Testing
@testable import FunctionAlps

@Suite("Wearables — sleep assembly and read-back aggregation")
struct WearableTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    @Test("A Watch night becomes one main sleep on the day it ended, in seconds")
    func watchNight() {
        let samples = [
            SleepSample(start: date("2026-09-03 23:00"), end: date("2026-09-03 23:20"), stage: .awake),
            SleepSample(start: date("2026-09-03 23:20"), end: date("2026-09-04 01:00"), stage: .core),
            SleepSample(start: date("2026-09-04 01:00"), end: date("2026-09-04 02:00"), stage: .deep),
            SleepSample(start: date("2026-09-04 02:00"), end: date("2026-09-04 02:10"), stage: .awake),
            SleepSample(start: date("2026-09-04 02:10"), end: date("2026-09-04 05:00"), stage: .core),
            SleepSample(start: date("2026-09-04 05:00"), end: date("2026-09-04 06:30"), stage: .rem),
        ]
        let nights = SleepAssembler.nights(from: samples, calendar: calendar)
        #expect(nights.count == 1)
        let n = nights[0]
        #expect(n.day == "2026-09-04")
        #expect(n.asleepSeconds == (100 + 60 + 170 + 90) * 60)
        #expect(n.deepSeconds == 3600)
        #expect(n.remSeconds == 5400)
        #expect(n.latencySeconds == 20 * 60)
        #expect(n.interruptions == 1)
        #expect(n.inBedSeconds == 7.5 * 3600)
        let rows = SleepAssembler.rows(for: n, timezoneOffset: 120)
        #expect(rows.contains { $0.dataTypeId == 2300 && $0.value == n.asleepSeconds })
        #expect(rows.contains { $0.dataTypeId == 2402 && $0.value == 1 })
        #expect(rows.allSatisfy { $0.dataSourceId == WearableSource.appleHealth && $0.day == "2026-09-04" })
    }

    @Test("A nap does not replace the night, and a gap splits sessions")
    func napAndNight() {
        let samples = [
            SleepSample(start: date("2026-09-03 23:00"), end: date("2026-09-04 06:00"), stage: .asleepUnspecified),
            SleepSample(start: date("2026-09-04 14:00"), end: date("2026-09-04 14:40"), stage: .asleepUnspecified),
        ]
        let nights = SleepAssembler.nights(from: samples, calendar: calendar)
        #expect(nights.count == 1)
        #expect(nights[0].asleepSeconds == 7 * 3600)
    }

    @Test("Read-back collapses sources: MAX for steps, MEDIAN for resting heart rate, seconds → hours for sleep")
    func aggregation() {
        let rows = [
            WearableLabeledRow(day: "2026-09-04", metric: "Steps", value: 8000, dataSourceId: 1_000_001, layer: "raw"),
            WearableLabeledRow(day: "2026-09-04", metric: "Steps", value: 9500, dataSourceId: 2, layer: "raw"),
            WearableLabeledRow(day: "2026-09-04", metric: "HeartRateResting", value: 52, dataSourceId: 1_000_001, layer: "raw"),
            WearableLabeledRow(day: "2026-09-04", metric: "HeartRateResting", value: 58, dataSourceId: 2, layer: "raw"),
            WearableLabeledRow(day: "2026-09-04", metric: "ThryveMainSleepDuration", value: 7 * 3600, dataSourceId: 1_000_001, layer: "analytics"),
            WearableLabeledRow(day: "2026-09-04", metric: "ThryveMainSleepInBedDuration", value: 8 * 3600, dataSourceId: 1_000_001, layer: "analytics"),
            WearableLabeledRow(day: "2026-09-04", metric: "SDNN", value: 45.25, dataSourceId: 1_000_001, layer: "raw"),
            WearableLabeledRow(day: "2026-09-04", metric: "SleepRelatedMortalityRisk", value: 3, dataSourceId: 2, layer: "risk"),
        ]
        let days = WearableAggregation.days(from: rows)
        #expect(days.count == 1)
        let d = days[0]
        #expect(d.steps == 9500)
        #expect(d.restingHr == 55)
        #expect(d.sleepHours == 7.0)
        #expect(d.sleepEfficiencyPct == 88)
        #expect(d.hrvMs == 45.3)
        #expect(d.sources == [1_000_001, 2])
    }

    @Test("The ingest batch encodes the wire shape the edge function reads")
    func wireShape() throws {
        let row = WearableDailyRow(day: "2026-09-04", metric: .steps, value: 8123.4, timezoneOffset: 120)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = String(decoding: try encoder.encode(WearableBatch(daily: [row])), as: UTF8.self)
        #expect(json.contains("\"data_type_name\":\"Steps\""))
        #expect(json.contains("\"data_type_id\":1000"))
        #expect(json.contains("\"data_source_id\":1000001"))
        #expect(json.contains("\"value\":8123"))
        #expect(json.contains("\"timezone_offset\":120"))
    }
}
