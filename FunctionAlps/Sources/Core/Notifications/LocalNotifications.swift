import Foundation
import UserNotifications

/// UNUserNotificationCenter, the thin way: permission, categories, and "make the pending set equal
/// this plan". Every request we own carries the `fa.` prefix so foreign ones are never touched.
@MainActor
final class LocalNotifications {
    static let prefix = "fa."
    static let categoryCheckin = "FA_CHECKIN"
    static let categoryMeal = "FA_MEAL"
    static let categoryReaction = "FA_REACTION"

    private let center = UNUserNotificationCenter.current()

    func registerCategories() {
        let checkin = UNNotificationCategory(identifier: Self.categoryCheckin, actions: [
            UNNotificationAction(identifier: "open", title: String(localized: "notif.action.checkin", defaultValue: "Check in now"), options: [.foreground]),
        ], intentIdentifiers: [])
        let meal = UNNotificationCategory(identifier: Self.categoryMeal, actions: [
            UNNotificationAction(identifier: "open", title: String(localized: "notif.action.log", defaultValue: "Log it"), options: [.foreground]),
        ], intentIdentifiers: [])
        let reaction = UNNotificationCategory(identifier: Self.categoryReaction, actions: [
            UNNotificationAction(identifier: "open", title: String(localized: "notif.action.rate", defaultValue: "Rate it"), options: [.foreground]),
            UNNotificationAction(identifier: "fine", title: String(localized: "notif.action.fine", defaultValue: "Felt fine"), options: []),
        ], intentIdentifiers: [])
        center.setNotificationCategories([checkin, meal, reaction])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks once; later calls return the stored answer.
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces our pending requests with the plan (adds new ids, removes the ones no longer planned).
    func apply(_ plan: [NotificationPlanner.Planned]) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        let wanted = Set(plan.map { Self.prefix + $0.id })
        let stale = pending.filter { !wanted.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        let existing = Set(pending)
        for p in plan where !existing.contains(Self.prefix + p.id) {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            content.threadIdentifier = p.threadId
            content.userInfo = ["route": p.route, "kind": p.kind.rawValue]
            content.categoryIdentifier = category(for: p.kind)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.prefix + p.id, content: content, trigger: trigger))
        }
    }

    /// One request, on top of what is pending (used right after a meal is logged).
    func add(_ p: NotificationPlanner.Planned) async {
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.body = p.body
        content.sound = .default
        content.threadIdentifier = p.threadId
        content.userInfo = ["route": p.route, "kind": p.kind.rawValue]
        content.categoryIdentifier = category(for: p.kind)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.fireAt)
        try? await center.add(UNNotificationRequest(identifier: Self.prefix + p.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.prefix + id])
        center.removeDeliveredNotifications(withIdentifiers: [Self.prefix + id])
    }

    func clearBadge() {
        center.setBadgeCount(0) { _ in }
    }

    private func category(for kind: NotificationPlanner.Kind) -> String {
        switch kind {
        case .morningCheckin, .middayCheckin, .eveningCheckin: Self.categoryCheckin
        case .lunchNotLogged, .dinnerNotLogged: Self.categoryMeal
        case .mealReaction: Self.categoryReaction
        case .weeklySummary, .wearableStale: ""
        }
    }
}
