import Foundation
import HealthKit
import Testing
@testable import FunctionAlps

@Suite("Wearables — D7: added daily metrics and relay provenance")
struct WearableRelayProvenanceTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich") ?? TimeZone(secondsFromGMT: 7200) ?? .current
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    private var snakeCase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    @Test("Flights climbed, body fat and body temperature carry their catalogue ids and value types")
    func addedMetrics() {
        #expect(WearableMetric.floorsClimbed.typeId == 1002 && WearableMetric.floorsClimbed.name == "FloorsClimbed" && WearableMetric.floorsClimbed.valueType == "LONG")
        #expect(WearableMetric.fatRatio.typeId == 5025 && WearableMetric.fatRatio.name == "FatRatio" && WearableMetric.fatRatio.valueType == "LONG")
        #expect(WearableMetric.bodyTemperature.typeId == 5040 && WearableMetric.bodyTemperature.name == "BodyTemperature" && WearableMetric.bodyTemperature.valueType == "DOUBLE")
        // The reader binds each to the right HealthKit type and aggregation.
        let flights = HealthKitReader.dailyTypes.first { $0.identifier == .flightsClimbed }
        let fat = HealthKitReader.dailyTypes.first { $0.identifier == .bodyFatPercentage }
        let temperature = HealthKitReader.dailyTypes.first { $0.identifier == .bodyTemperature }
        #expect(flights?.metric == .floorsClimbed && flights?.options == .cumulativeSum)
        #expect(fat?.metric == .fatRatio && fat?.options == .discreteAverage)
        #expect(temperature?.metric == .bodyTemperature && temperature?.options == .discreteAverage)
        #expect(!HealthKitReader.dailyTypes.contains { $0.identifier == .bloodGlucose }) // parked (CGM later)
        // Percent is rounded like every LONG; temperature keeps two decimals.
        #expect(WearableDailyRow(day: "2026-09-14", metric: .fatRatio, value: 23.6, timezoneOffset: 120).value == 24)
        #expect(WearableDailyRow(day: "2026-09-14", metric: .bodyTemperature, value: 36.734, timezoneOffset: 120).value == 36.73)
    }

    @Test("An epoch row built with a HealthKit uuid + bundle encodes source_record_id / source_device_id; without them the keys are absent")
    func epochProvenanceOnTheWire() throws {
        let start = Date(timeIntervalSince1970: 1_789_300_000)
        let end = start.addingTimeInterval(3600)
        let row = WearableEpochRow(start: start, end: end, metric: .workout, value: 60, valueText: "running", timezoneOffset: 120, details: ["duration_min": 60],
                                   sourceRecordId: "3F2504E0-4F89-41D3-9A0C-0305E82C3301", sourceDeviceId: "com.apple.health")
        let json = String(decoding: try snakeCase.encode(WearableBatch(epoch: [row])), as: UTF8.self)
        #expect(json.contains("\"source_record_id\":\"3F2504E0-4F89-41D3-9A0C-0305E82C3301\""))
        #expect(json.contains("\"source_device_id\":\"com.apple.health\""))
        #expect(json.contains("\"data_type_name\":\"workout\""))

        let bare = WearableEpochRow(start: start, end: end, metric: .workout, value: 60, timezoneOffset: 120)
        let bareJson = String(decoding: try snakeCase.encode(WearableBatch(epoch: [bare])), as: UTF8.self)
        #expect(!bareJson.contains("source_record_id") && !bareJson.contains("source_device_id"))
        #expect(bare.sourceRecordId == nil && bare.sourceDeviceId == nil)
    }

    @Test("A night assembled from several samples keeps the FIRST sample's provenance, and its daily rows carry it")
    func nightKeepsFirstSampleProvenance() throws {
        let samples = [
            SleepSample(start: date("2026-09-13 23:10"), end: date("2026-09-14 02:00"), stage: .core, sourceRecordId: "uuid-first", sourceDeviceId: "com.apple.health"),
            SleepSample(start: date("2026-09-14 02:00"), end: date("2026-09-14 03:00"), stage: .deep, sourceRecordId: "uuid-second", sourceDeviceId: "com.apple.health"),
            SleepSample(start: date("2026-09-14 03:00"), end: date("2026-09-14 06:30"), stage: .rem, sourceRecordId: "uuid-third", sourceDeviceId: "com.apple.health"),
            // Out of order on purpose: the assembler sorts by start, so "first" is the earliest sample.
            SleepSample(start: date("2026-09-13 23:00"), end: date("2026-09-13 23:10"), stage: .awake, sourceRecordId: "uuid-earliest", sourceDeviceId: "com.apple.health"),
        ]
        let nights = SleepAssembler.nights(from: samples, calendar: calendar)
        let night = try #require(nights.first)
        #expect(nights.count == 1 && night.day == "2026-09-14")
        #expect(night.sourceRecordId == "uuid-earliest" && night.sourceDeviceId == "com.apple.health")
        let rows = SleepAssembler.rows(for: night, timezoneOffset: 120)
        #expect(!rows.isEmpty && rows.allSatisfy { $0.sourceRecordId == "uuid-earliest" && $0.sourceDeviceId == "com.apple.health" })
        let json = String(decoding: try snakeCase.encode(WearableBatch(daily: rows)), as: UTF8.self)
        #expect(json.contains("\"source_record_id\":\"uuid-earliest\""))

        // Samples without provenance (fixtures, third-party writers) still assemble; the keys stay nil.
        let plain = SleepAssembler.nights(from: [SleepSample(start: date("2026-09-12 23:00"), end: date("2026-09-13 06:00"), stage: .asleepUnspecified)], calendar: calendar)
        #expect(plain.first?.sourceRecordId == nil && plain.first?.sourceDeviceId == nil)
    }
}
