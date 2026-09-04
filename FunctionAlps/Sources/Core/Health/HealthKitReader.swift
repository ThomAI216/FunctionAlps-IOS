import Foundation
import HealthKit

/// Everything the app reads from Apple Health, in one place. The phone is the source: Apple Watch
/// writes into HealthKit on the paired iPhone, so a watch needs no app of ours — reading the
/// store covers the Watch, the phone's own motion data and any third-party device that syncs to Health.
///
/// Read-only. HealthKit never reveals whether READ access was granted (a denied type simply returns
/// no data), so "connected" is the member's own tap recorded on this phone, not a HealthKit fact.
final class HealthKitReader: @unchecked Sendable {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The quantity types the daily statistics cover, with their catalogue metric and the unit we read them in.
    struct DailyType: @unchecked Sendable {
        let identifier: HKQuantityTypeIdentifier
        let metric: WearableMetric
        let unit: HKUnit
        /// `.cumulativeSum` for counts, `.discreteAverage` for point-in-time readings.
        let options: HKStatisticsOptions
    }

    static let dailyTypes: [DailyType] = [
        DailyType(identifier: .stepCount, metric: .steps, unit: .count(), options: .cumulativeSum),
        DailyType(identifier: .distanceWalkingRunning, metric: .distance, unit: .meter(), options: .cumulativeSum),
        DailyType(identifier: .activeEnergyBurned, metric: .activeCalories, unit: .kilocalorie(), options: .cumulativeSum),
        DailyType(identifier: .basalEnergyBurned, metric: .burnedCalories, unit: .kilocalorie(), options: .cumulativeSum),
        DailyType(identifier: .appleExerciseTime, metric: .activityDuration, unit: .minute(), options: .cumulativeSum),
        DailyType(identifier: .restingHeartRate, metric: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage),
        DailyType(identifier: .heartRate, metric: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage),
        DailyType(identifier: .heartRateVariabilitySDNN, metric: .hrvSDNN, unit: .secondUnit(with: .milli), options: .discreteAverage),
        DailyType(identifier: .respiratoryRate, metric: .respirationRate, unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage),
        DailyType(identifier: .oxygenSaturation, metric: .spo2, unit: .percent(), options: .discreteAverage),
        DailyType(identifier: .vo2Max, metric: .vo2max, unit: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())), options: .discreteAverage),
        DailyType(identifier: .bodyMass, metric: .weight, unit: .gramUnit(with: .kilo), options: .discreteAverage),
    ]

    /// Every type the authorisation sheet asks for: the daily quantities, sleep, and workouts.
    static var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>(dailyTypes.map { HKQuantityType($0.identifier) })
        set.insert(HKCategoryType(.sleepAnalysis))
        set.insert(HKObjectType.workoutType())
        return set
    }

    /// Shows Apple's permission sheet (once per type; later calls return immediately).
    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: Daily statistics

    /// One value per local day for a quantity type, oldest first, days without data omitted.
    func dailyValues(_ type: DailyType, from start: Date, to end: Date, calendar: Calendar = .current) async throws -> [(day: Date, value: Double)] {
        let quantityType = HKQuantityType(type.identifier)
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: quantityType, predicate: window),
            options: type.options,
            anchorDate: calendar.startOfDay(for: end),
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var out: [(Date, Double)] = []
        for stats in collection.statistics() {
            let quantity = type.options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
            guard let quantity else { continue }
            var value = quantity.doubleValue(for: type.unit)
            if type.identifier == .oxygenSaturation { value *= 100 } // HealthKit's percent is 0–1
            out.append((stats.startDate, value))
        }
        return out.map { (day: $0.0, value: $0.1) }
    }

    // MARK: Sleep

    /// Every sleep sample in the window, mapped to the app's stages (the Watch writes core/deep/REM/awake;
    /// third-party apps often write in-bed or unspecified).
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        let type = HKCategoryType(.sleepAnalysis)
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepSample.Stage
            switch value {
            case .inBed: stage = .inBed
            case .awake: stage = .awake
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            case .asleepUnspecified: stage = .asleepUnspecified
            @unknown default: return nil
            }
            return SleepSample(start: sample.startDate, end: sample.endDate, stage: stage)
        }
    }

    // MARK: Workouts

    struct Workout: Sendable, Equatable {
        let start: Date
        let end: Date
        let activityName: String
        let durationMinutes: Double
        let energyKcal: Double?
        let distanceM: Double?
    }

    func workouts(from start: Date, to end: Date) async throws -> [Workout] {
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(window)], sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store)
        return samples.map { w in
            let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
            return Workout(start: w.startDate, end: w.endDate, activityName: Self.name(of: w.workoutActivityType), durationMinutes: w.duration / 60, energyKcal: energy, distanceM: distance)
        }
    }

    private static func name(of type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "running"
        case .walking: "walking"
        case .cycling: "cycling"
        case .hiking: "hiking"
        case .swimming: "swimming"
        case .yoga: "yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: "strength"
        case .highIntensityIntervalTraining: "hiit"
        case .rowing: "rowing"
        case .elliptical: "elliptical"
        case .pilates: "pilates"
        case .downhillSkiing, .crossCountrySkiing, .snowboarding: "snow_sports"
        default: "other_\(type.rawValue)"
        }
    }

    // MARK: Background delivery

    /// Asks HealthKit to wake the app when these types change, and keeps an observer per type. The observer's
    /// completion handler MUST be called or HealthKit stops delivering. Not available on the Simulator.
    func enableBackgroundDelivery(onChange: @escaping @Sendable () -> Void) async {
        let types: [HKSampleType] = [
            HKQuantityType(.stepCount), HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis), HKObjectType.workoutType(),
        ]
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if error == nil { onChange() }
                completion()
            }
            store.execute(query)
            // Steps arrive constantly; hourly is the finest HealthKit allows for them anyway.
            let frequency: HKUpdateFrequency = type == HKQuantityType(.stepCount) ? .hourly : .immediate
            _ = try? await store.enableBackgroundDelivery(for: type, frequency: frequency)
        }
    }

    func disableBackgroundDelivery() async {
        _ = try? await store.disableAllBackgroundDelivery()
    }

    enum HealthKitError: Error, LocalizedError {
        case unavailable
        var errorDescription: String? {
            String(localized: "wearables.unavailable", defaultValue: "Apple Health isn't available on this device.")
        }
    }
}
