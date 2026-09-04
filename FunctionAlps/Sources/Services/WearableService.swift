import Foundation
import Observation

/// Apple Health on this phone → CM OS (`wearable-ingest`). The phone reads HealthKit, reduces it to the
/// catalogue's daily metrics, and posts batches; the server stores the raw submission and upserts the
/// normalised rows on their natural keys, so re-sending a day is safe.
///
/// "Connected" is a fact about THIS phone (the member tapped Connect and Apple's sheet was shown),
/// kept in UserDefaults with the last sync; HealthKit itself never says whether reading was allowed.
@MainActor
@Observable
final class WearableService {
    enum SyncState: Equatable { case idle, syncing, failed(String) }

    private(set) var isConnected: Bool
    private(set) var lastSyncAt: Date?
    private(set) var lastSyncCount: Int
    private(set) var state: SyncState = .idle

    private let backend: any FunctionAlpsBackend
    private let reader = HealthKitReader()
    private let defaults: UserDefaults
    private let calendar: Calendar
    private var syncTask: Task<Void, Never>?
    /// Set by connect(); travels with the next batch so CM OS records the connection even when
    /// the phone has no health data yet.
    private var pendingConnection: String?

    private enum Key {
        static let connected = "fa.wearables.appleHealth.connected"
        static let lastSync = "fa.wearables.appleHealth.lastSync"
        static let lastCount = "fa.wearables.appleHealth.lastCount"
    }

    /// First sync backfills this much; later syncs re-send the last few days (values settle late).
    static let backfillDays = 30
    static let resyncDays = 3

    init(backend: any FunctionAlpsBackend, defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.backend = backend
        self.defaults = defaults
        self.calendar = calendar
        isConnected = defaults.bool(forKey: Key.connected)
        lastSyncAt = defaults.object(forKey: Key.lastSync) as? Date
        lastSyncCount = defaults.integer(forKey: Key.lastCount)
    }

    static var isAvailable: Bool { HealthKitReader.isAvailable }

    // MARK: Connect / disconnect

    /// Shows Apple's permission sheet, marks the phone connected, backfills, and arms background delivery.
    func connect() async throws {
        try await reader.requestAuthorization()
        isConnected = true
        pendingConnection = "connected"
        defaults.set(true, forKey: Key.connected)
        await armBackgroundDelivery()
        await sync()
    }

    /// Stops syncing from this phone. Reading permission itself is revoked in Settings → Health → Data Access.
    func disconnect() async {
        isConnected = false
        pendingConnection = nil
        lastSyncAt = nil
        lastSyncCount = 0
        state = .idle
        defaults.removeObject(forKey: Key.connected)
        defaults.removeObject(forKey: Key.lastSync)
        defaults.removeObject(forKey: Key.lastCount)
        await reader.disableBackgroundDelivery()
        // Best effort: the phone is disconnected either way; CM OS just learns about it.
        _ = try? await backend.ingestWearable(WearableBatch(connection: "disconnected"))
    }

    /// Called at launch: re-registers the observers when the member connected on an earlier run.
    func armBackgroundDeliveryIfConnected() async {
        guard isConnected else { return }
        await armBackgroundDelivery()
    }

    private func armBackgroundDelivery() async {
        await reader.enableBackgroundDelivery { [weak self] in
            Task { @MainActor in await self?.sync() }
        }
    }

    // MARK: Sync

    /// Reads the window, builds the batch, posts it. Coalesces overlapping calls (background wake-ups arrive in bursts).
    func sync() async {
        guard isConnected else { return }
        if let running = syncTask { await running.value; return }
        let task = Task { await self.runSync() }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private func runSync() async {
        state = .syncing
        do {
            var batch = try await buildBatch()
            batch.connection = pendingConnection
            if !batch.isBlank {
                _ = try await backend.ingestWearable(batch)
            }
            pendingConnection = nil
            lastSyncAt = Date()
            lastSyncCount = batch.count
            defaults.set(lastSyncAt, forKey: Key.lastSync)
            defaults.set(batch.count, forKey: Key.lastCount)
            state = .idle
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "wearables.sync")
            state = .failed(error.userMessage)
        } catch {
            Log.data.error("wearables.sync: \(String(describing: error), privacy: .public)")
            state = .failed(String(localized: "wearables.syncFailed", defaultValue: "Apple Health couldn't be read just now. Try again in a moment."))
        }
    }

    /// The window: 30 days on the first sync, otherwise from a few days before the last sync.
    private var windowStart: Date {
        let days = lastSyncAt == nil ? Self.backfillDays : Self.resyncDays
        let base = lastSyncAt.map { min($0, Date()) } ?? Date()
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -days, to: base) ?? base)
    }

    func buildBatch() async throws -> WearableBatch {
        let end = Date()
        let start = windowStart
        let offset = TimeZone.current.secondsFromGMT() / 60
        var batch = WearableBatch()

        for type in HealthKitReader.dailyTypes {
            let values = (try? await reader.dailyValues(type, from: start, to: end, calendar: calendar)) ?? []
            for (day, value) in values where value > 0 {
                batch.daily.append(WearableDailyRow(day: ISO8601.day(day, calendar: calendar), metric: type.metric, value: value, timezoneOffset: offset, recordedAt: day))
            }
        }

        // Sleep: read a day earlier so the night that ended on the first day of the window is whole.
        let sleepStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let sleep = (try? await reader.sleepSamples(from: sleepStart, to: end)) ?? []
        for night in SleepAssembler.nights(from: sleep, calendar: calendar) where night.day >= ISO8601.day(start, calendar: calendar) {
            batch.daily.append(contentsOf: SleepAssembler.rows(for: night, timezoneOffset: offset))
        }

        // Workouts as timed rows (native-only name; the dashboard reads them by name).
        let workouts = (try? await reader.workouts(from: start, to: end)) ?? []
        for w in workouts {
            var details: [String: Double] = ["duration_min": (w.durationMinutes * 10).rounded() / 10]
            if let kcal = w.energyKcal { details["energy_kcal"] = kcal.rounded() }
            if let m = w.distanceM { details["distance_m"] = m.rounded() }
            batch.epoch.append(WearableEpochRow(start: w.start, end: w.end, metric: .workout, value: w.durationMinutes.rounded(), valueText: w.activityName, timezoneOffset: offset, details: details))
        }
        return batch
    }

    // MARK: Read-back (what CM OS holds, any source)

    func recentDays(patientId: String, days: Int = 14) async -> [WearableDay] {
        let since = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let rows = (try? await backend.wearableDaily(patientId: patientId, since: ISO8601.day(since, calendar: calendar))) ?? []
        return WearableAggregation.days(from: rows)
    }

    func connections(patientId: String) async -> [WearableConnectionRow] {
        (try? await backend.wearableConnections(patientId: patientId)) ?? []
    }
}
