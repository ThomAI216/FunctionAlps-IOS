import Foundation
import Observation
import UIKit
import UserNotifications

/// The phone's notification engine: preferences (CM OS row), the local plan (`NotificationPlanner` →
/// `LocalNotifications`), the APNs token (uploaded to the same row so `push-send` can reach this phone),
/// and taps (→ `AppRouter.open`). Re-planned on every foreground, after every meal or check-in.
/// Meal reminders follow the member's own schedule (`member_meal_schedule`), read with the preferences.
@MainActor
@Observable
final class NotificationService {
    private(set) var prefs: NotificationPrefs = .default
    /// The member's meal schedule as last read or saved; nil until the first read succeeds.
    private(set) var mealSchedule: MealSchedule?
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var lastPlanCount = 0
    private(set) var apnsRegistered = false

    private let backend: any FunctionAlpsBackend
    private let local = LocalNotifications()
    private let defaults: UserDefaults
    /// Shared with `MealService`, which labels a new meal by the member's own times.
    private let scheduleBox: MealScheduleBox
    private var patientId: String?
    private var pendingToken: Data?
    /// Today as Home last saw it — a re-plan from Settings must not forget what is already done.
    private var lastSnapshot: TodaySnapshot?
    /// Meals logged on this phone since, from any screen: Home's snapshot may not have them yet.
    private var mealsLoggedHere: [NotificationPlanner.LoggedMeal] = []

    private enum Key {
        static let askedOnce = "fa.notifications.askedOnce"
        static let mealSetupOffered = "fa.notifications.mealSetupOffered"
    }

    init(backend: any FunctionAlpsBackend, defaults: UserDefaults = .standard, scheduleBox: MealScheduleBox = MealScheduleBox()) {
        self.backend = backend
        self.defaults = defaults
        self.scheduleBox = scheduleBox
        mealSetupOffered = defaults.bool(forKey: Key.mealSetupOffered)
        local.registerCategories()
    }

    var hasAskedOnce: Bool { defaults.bool(forKey: Key.askedOnce) }

    // MARK: Permission

    /// The system prompt, once, at a moment that makes sense (first meal logged / first check-in / Settings).
    func askIfNeeded() async {
        authorization = await local.authorizationStatus()
        guard authorization == .notDetermined else { return }
        defaults.set(true, forKey: Key.askedOnce)
        _ = await local.requestAuthorization()
        authorization = await local.authorizationStatus()
        if authorization == .authorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    func refreshAuthorization() async {
        authorization = await local.authorizationStatus()
        if authorization == .authorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    // MARK: Preferences

    /// Reads the row once per member (Settings re-reads on open); later calls only flush a waiting token.
    /// The meal schedule rides along: read (and seeded server-side) once per member, retried until it lands.
    func loadPrefs(patientId: String, force: Bool = false) async {
        let fresh = self.patientId != patientId
        self.patientId = patientId
        if fresh {
            mealSchedule = nil
            scheduleBox.set(nil)
            lastSnapshot = nil
            mealsLoggedHere = []
        }
        if fresh || force, let row = try? await backend.notificationPrefs(patientId: patientId) { prefs = row.prefs }
        if fresh || force || mealSchedule == nil { _ = try? await loadMealSchedule() }
        if let token = pendingToken { await upload(token: token) }
    }

    func save(_ new: NotificationPrefs) async throws {
        guard let patientId else { return }
        try await backend.saveNotificationPrefs(NotificationPrefsRow.write(new, patientId: patientId))
        prefs = new
    }

    // MARK: Meal schedule (member_meal_schedule)

    /// Reads the member's schedule; the server creates it on the first read (intake, profile, defaults).
    /// An empty answer means no linked profile yet — `AppError.notFound`, never a made-up schedule.
    @discardableResult
    func loadMealSchedule() async throws -> MealSchedule {
        let rows = try await backend.mealSchedule()
        let entries = rows.compactMap(\.entry)
        guard !entries.isEmpty else { throw AppError.notFound }
        let schedule = MealSchedule(entries: entries)
        mealSchedule = schedule
        scheduleBox.set(schedule)
        return schedule
    }

    /// Writes only the rows that changed since the last read or save. On failure nothing is marked saved,
    /// so the next save carries these changes too.
    func saveMealSchedule(_ new: MealSchedule) async throws {
        guard let patientId, let old = mealSchedule else { throw AppError.notFound }
        let changed = new.changes(since: old)
        guard !changed.isEmpty else { return }
        try await backend.saveMealSchedule(changed.map { MealScheduleRow.write($0, patientId: patientId) })
        mealSchedule = new
        scheduleBox.set(new)
    }

    /// The 20-second "when do you usually eat?" setup: offered once per phone, only to a member who allowed
    /// reminders, has meal reminders on, and has not chosen a single time yet.
    var shouldOfferMealSetup: Bool {
        (authorization == .authorized || authorization == .provisional)
            && prefs.mealRemindersEnabled
            && mealSchedule?.awaitsSetup == true
            && !mealSetupOffered
    }

    private(set) var mealSetupOffered = false

    func markMealSetupOffered() {
        mealSetupOffered = true
        defaults.set(true, forKey: Key.mealSetupOffered)
    }

    // MARK: APNs token

    func deviceTokenReceived(_ data: Data) {
        pendingToken = data
        Task { await upload(token: data) }
    }

    private func upload(token: Data) async {
        guard let patientId else { return }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
        let write = PushTokenWrite(patientId: patientId, apnsToken: hex, apnsEnvironment: environment, apnsTokenUpdatedAt: ISO8601.string(Date()), devicePlatform: "ios", appVersion: version, timezone: TimeZone.current.identifier)
        if (try? await backend.savePushToken(write)) != nil { apnsRegistered = true; pendingToken = nil }
    }

    // MARK: The local plan

    /// Rebuilds the pending set from today's state. `snapshot` nil = keep the last known state of the same day
    /// (a re-plan from Settings must not re-add a check-in or a meal already done).
    /// Reactions for the recent meals are read here (one small PostgREST call) so a rated meal never gets its 2.5 h nudge.
    func replan(snapshot: TodaySnapshot?, wearables: WearableService?) async {
        guard authorization == .authorized || authorization == .provisional else { return }
        if let snapshot { lastSnapshot = snapshot }
        let known = snapshot ?? lastSnapshot.flatMap { $0.day == ISO8601.dayString(Date()) ? $0 : nil }
        var state = NotificationPlanner.State(now: Date())
        if let snapshot = known {
            state.momentsDone = Set(snapshot.moments.map(\.slot))
            state.mealsToday = snapshot.meals.map { NotificationPlanner.LoggedMeal(at: $0.loggedAt, type: $0.mealType) }
            let cutoff = Date().addingTimeInterval(-4 * 3600)
            let recent = snapshot.meals.filter { $0.loggedAt > cutoff && $0.isAnalysed }
            var rated: Set<String> = ratedLocally
            if !recent.isEmpty, let patientId, let felt = try? await backend.mealReactions(patientId: patientId, since: cutoff) {
                rated.formUnion(felt.keys)
            }
            state.unratedRecentMeals = recent.filter { !rated.contains($0.id) }.map { (id: $0.id, loggedAt: $0.loggedAt) }
        }
        let today = ISO8601.dayString(Date())
        mealsLoggedHere.removeAll { ISO8601.dayString($0.at) != today }
        state.mealsToday += mealsLoggedHere
        if let wearables { state.appleHealthConnected = wearables.isConnected; state.appleHealthLastSync = wearables.lastSyncAt }
        let plan = NotificationPlanner.finalized(NotificationPlanner.plan(prefs: prefs, schedule: mealSchedule, state: state), prefs: prefs)
        // Schedule not read yet (offline launch): leave the meal reminders already pending as they are.
        let keep: Set<NotificationPlanner.Kind> = mealSchedule == nil && prefs.mealRemindersEnabled
            ? Set(NotificationPlanner.Kind.allCases.filter(\.isMealSlot)) : []
        await local.apply(plan, keepingKinds: keep)
        lastPlanCount = plan.count
    }

    /// Meals rated on this phone this session (so a replan racing the write never re-adds the nudge).
    private var ratedLocally: Set<String> = []

    /// A meal was just logged: today's reminder for that meal goes at once (whichever screen logged it), and
    /// its 2.5 h follow-up joins the plan without waiting for the next replan.
    func mealLogged(id: String, at: Date) async {
        let schedule = mealSchedule ?? .defaults
        let slot = schedule.slot(forMealAt: at, type: nil, calendar: .current)
        mealsLoggedHere.append(NotificationPlanner.LoggedMeal(at: at, type: nil))
        local.cancel(id: "\(NotificationPlanner.Kind.meal(slot).rawValue).\(ISO8601.dayString(at))")
        guard prefs.postMealFollowupEnabled, authorization == .authorized || authorization == .provisional else { return }
        let state = NotificationPlanner.State(now: Date(), unratedRecentMeals: [(id: id, loggedAt: at)])
        var only = NotificationPlanner.plan(prefs: NotificationPrefs(morningEnabled: false, middayEnabled: false, eveningEnabled: false, mealRemindersEnabled: false, postMealFollowupEnabled: true, weeklySummaryEnabled: false), state: state)
        only = NotificationPlanner.respectingQuietHours(only, prefs: prefs)
        // apply() removes what is not in the plan — so merge with the pending set by re-adding just this one.
        for p in only { await local.add(p) }
    }

    func mealRated(id: String) {
        ratedLocally.insert(id)
        local.cancel(id: "\(NotificationPlanner.Kind.mealReaction.rawValue).\(id)")
    }

    /// "Felt fine" tapped on the reaction banner: an 8/10 with zero symptoms, without opening the app.
    func quickFine(mealId: String) {
        mealRated(id: mealId)
        guard let patientId else { return }
        let backend = self.backend
        Task {
            let write = MealReactionWrite(patientId: patientId, mealLogId: mealId, overall: 7, bloating: 0, fullness: 0, gasBurden: 0,
                                          burning: 0, fatigue: 0, digestion: 7, energy: nil,
                                          responses: ["overall": 7, "digestion": 7], reactionFlags: nil, reactionTime: ISO8601.string(Date()))
            do { try await backend.saveMealReaction(write) } catch { Log.data.error("quickFine: \(String(describing: error), privacy: .public)") }
        }
    }

    func momentDone(_ slot: MomentSlot, day: String) {
        let kind: NotificationPlanner.Kind = slot == .morning ? .morningCheckin : slot == .midday ? .middayCheckin : .eveningCheckin
        local.cancel(id: "\(kind.rawValue).\(day)")
    }

    func clearBadge() { local.clearBadge() }
}
