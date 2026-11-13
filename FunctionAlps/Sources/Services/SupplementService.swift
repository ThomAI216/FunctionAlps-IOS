import Foundation
import Observation
import UserNotifications

/// The member's supplements as one shared, observable value: Home's card, the Plan's list and each supplement's
/// page read the same load. A tick shows at once and is written behind (put back if the write fails); every fresh
/// read re-plans the phone's grouped reminders (`NotificationService` → `SupplementReminders`), so a ticked
/// moment never reminds and a new day's reminders exist before the app is opened.
@MainActor
@Observable
final class SupplementService {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded([Supplement])
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// A tick the server refused or could not take (shown once on the page, then cleared).
    private(set) var tickError: String?

    private let backend: any FunctionAlpsBackend
    private let auth: AuthService
    private let notifications: NotificationService
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    @ObservationIgnored private var loading = false

    private enum Key { static let explained = "fa.supplements.reminderExplained" }

    init(backend: any FunctionAlpsBackend, auth: AuthService, notifications: NotificationService,
         defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.auth = auth
        self.notifications = notifications
        self.defaults = defaults
        self.now = now
    }

    var supplements: [Supplement] {
        if case .loaded(let list) = phase { return list }
        return []
    }

    func supplement(id: String) -> Supplement? { supplements.first { $0.id == id } }

    /// Today's ticks for Home (due today, active), in day order.
    func rows() -> [SupplementLogic.Row] { SupplementLogic.rows(supplements, now: now()) }

    // MARK: Reading

    /// Keeps what is on screen while refreshing; only a first load shows the skeleton.
    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if case .loaded = phase {} else { phase = .loading }
        do {
            let list = try await backend.supplements()
            phase = .loaded(list)
            await notifications.updateSupplements(list)
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "supplements.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if supplements.isEmpty { phase = .failed(error.userMessage) }
        } catch {
            Log.data.error("supplements.load: \(String(describing: error), privacy: .public)")
            if supplements.isEmpty { phase = .failed(AppError.unknown(detail: String(describing: error)).userMessage) }
        }
    }

    func retry() async { await load() }

    // MARK: Ticking

    /// Ticks (or un-ticks) one moment of today. Optimistic; a failed write puts the supplement back.
    func setTaken(_ taken: Bool, supplementId: String, moment: SupplementMoment) async {
        guard case .loaded(let list) = phase, let index = list.firstIndex(where: { $0.id == supplementId }) else { return }
        let previous = list[index]
        guard previous.isTaken(moment) != taken else { return }
        tickError = nil
        var updated = list
        updated[index] = previous.setting(moment, taken: taken, at: now())
        phase = .loaded(updated)
        await notifications.updateSupplements(updated)
        do {
            try await backend.logSupplement(planId: supplementId, moment: moment, taken: taken, day: nil)
            if taken { await notifications.supplementAnswered(moment: moment, day: ISO8601.dayString(now())) }
            await load()   // the observance and the strip follow the tick
        } catch {
            if case .loaded(var current) = phase, let i = current.firstIndex(where: { $0.id == supplementId }) {
                current[i] = previous
                phase = .loaded(current)
                await notifications.updateSupplements(current)
            }
            report(error, context: "supplements.tick")
            tickError = (error as? AppError)?.userMessage ?? AppError.unknown(detail: String(describing: error)).userMessage
        }
    }

    func clearTickError() { tickError = nil }

    /// The "Taken" button on a grouped reminder: every supplement of the group, for the day the reminder was for.
    /// Works from a cold start (nothing loaded): the writes go straight to the server, then the list is read.
    func logTaken(_ group: SupplementReminders.Group) async {
        let today = ISO8601.dayString(now())
        for id in group.supplementIds {
            do {
                try await backend.logSupplement(planId: id, moment: group.moment, taken: true, day: group.day == today ? nil : group.day)
            } catch {
                report(error, context: "supplements.notificationTaken")
            }
        }
        await notifications.supplementAnswered(moment: group.moment, day: group.day)
        await load()
    }

    /// "Later" on a grouped reminder.
    func snooze(_ group: SupplementReminders.Group) async {
        await notifications.snoozeSupplements(moment: group.moment, day: group.day, ids: group.supplementIds)
    }

    private func report(_ error: Error, context: StaticString) {
        guard let appError = error as? AppError else { return }
        Log.error(appError, in: Log.data, context: context)
        if case .unauthorized = appError { Task { await auth.handleUnauthorized() } }
    }

    // MARK: The first-time explanation

    /// Reminders are ON by default, so the only ask is the system's notification permission — explained once, the
    /// first time supplements are shown, and only while the phone has not been asked yet.
    var shouldExplainReminders: Bool {
        #if DEBUG
        if Showcase.isOn { return false }   // a screenshot never opens on the permission explanation
        #endif
        guard !defaults.bool(forKey: Key.explained), notifications.authorization == .notDetermined,
              notifications.prefs.supplementRemindersEnabled else { return false }
        return supplements.contains { $0.isActive && $0.dueToday }
    }

    func markRemindersExplained() { defaults.set(true, forKey: Key.explained) }

    /// "Turn on reminders" on the explanation: the system prompt, then the plan with the supplements in it.
    func enableReminders() async {
        markRemindersExplained()
        await notifications.askIfNeeded()
        await notifications.replan(snapshot: nil, wearables: nil)
    }
}
