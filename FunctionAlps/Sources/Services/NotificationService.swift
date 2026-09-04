import Foundation
import Observation
import UIKit
import UserNotifications

/// The phone's notification engine: preferences (CM OS row), the local plan (`NotificationPlanner` →
/// `LocalNotifications`), the APNs token (uploaded to the same row so `push-send` can reach this phone),
/// and taps (→ `AppRouter.open`). Re-planned on every foreground, after every meal or check-in.
@MainActor
@Observable
final class NotificationService {
    private(set) var prefs: NotificationPrefs = .default
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var lastPlanCount = 0
    private(set) var apnsRegistered = false

    private let backend: any FunctionAlpsBackend
    private let local = LocalNotifications()
    private let defaults: UserDefaults
    private var patientId: String?
    private var pendingToken: Data?

    private enum Key { static let askedOnce = "fa.notifications.askedOnce" }

    init(backend: any FunctionAlpsBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
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
    func loadPrefs(patientId: String, force: Bool = false) async {
        let fresh = self.patientId != patientId
        self.patientId = patientId
        if fresh || force, let row = try? await backend.notificationPrefs(patientId: patientId) { prefs = row.prefs }
        if let token = pendingToken { await upload(token: token) }
    }

    func save(_ new: NotificationPrefs) async throws {
        guard let patientId else { return }
        try await backend.saveNotificationPrefs(NotificationPrefsRow.write(new, patientId: patientId))
        prefs = new
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

    /// Rebuilds the pending set from today's state. `snapshot` nil = keep the last known state (e.g. before load).
    /// Reactions for the recent meals are read here (one small PostgREST call) so a rated meal never gets its 2.5 h nudge.
    func replan(snapshot: TodaySnapshot?, wearables: WearableService?) async {
        guard authorization == .authorized || authorization == .provisional else { return }
        var state = NotificationPlanner.State(now: Date())
        if let snapshot {
            state.momentsDone = Set(snapshot.moments.map(\.slot))
            state.mealsToday = snapshot.meals.map(\.loggedAt)
            let cutoff = Date().addingTimeInterval(-4 * 3600)
            let recent = snapshot.meals.filter { $0.loggedAt > cutoff && $0.isAnalysed }
            var rated: Set<String> = ratedLocally
            if !recent.isEmpty, let patientId, let felt = try? await backend.mealReactions(patientId: patientId, since: cutoff) {
                rated.formUnion(felt.keys)
            }
            state.unratedRecentMeals = recent.filter { !rated.contains($0.id) }.map { (id: $0.id, loggedAt: $0.loggedAt) }
        }
        if let wearables { state.appleHealthConnected = wearables.isConnected; state.appleHealthLastSync = wearables.lastSyncAt }
        let plan = NotificationPlanner.respectingQuietHours(NotificationPlanner.plan(prefs: prefs, state: state), prefs: prefs)
        await local.apply(plan)
        lastPlanCount = plan.count
    }

    /// Meals rated on this phone this session (so a replan racing the write never re-adds the nudge).
    private var ratedLocally: Set<String> = []

    /// A meal was just logged: its 2.5 h follow-up joins the plan without waiting for the next replan.
    func mealLogged(id: String, at: Date) async {
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
            let write = MealReactionWrite(patientId: patientId, mealLogId: mealId, overall: 8, bloating: 0, fullness: 0, gasBurden: 0,
                                          responses: ["overall": 8], reactionFlags: nil, reactionTime: ISO8601.string(Date()))
            do { try await backend.saveMealReaction(write) } catch { Log.data.error("quickFine: \(String(describing: error), privacy: .public)") }
        }
    }

    func momentDone(_ slot: MomentSlot, day: String) {
        let kind: NotificationPlanner.Kind = slot == .morning ? .morningCheckin : slot == .midday ? .middayCheckin : .eveningCheckin
        local.cancel(id: "\(kind.rawValue).\(day)")
    }

    func clearBadge() { local.clearBadge() }
}
