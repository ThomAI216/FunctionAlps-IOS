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

    /// Replaces our pending requests with the plan: adds new ids, removes the ones no longer planned, and
    /// re-adds an id whose time or words changed (a moved dinner must not keep ringing at the old time).
    /// `keepingKinds`: pending requests of these kinds are left alone when the plan has none of them — the
    /// meal slots while the member's schedule is not known yet.
    func apply(_ plan: [NotificationPlanner.Planned], keepingKinds: Set<NotificationPlanner.Kind> = []) async {
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.prefix) }
        let wanted = Dictionary(plan.map { (Self.prefix + $0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = pending.filter { request in
            guard wanted[request.identifier] == nil else { return false }
            let kind = (request.content.userInfo["kind"] as? String).flatMap(NotificationPlanner.Kind.init(rawValue:))
            return kind.map { keepingKinds.contains($0) } ?? false
        }.map(\.identifier)
        var stale = pending.map(\.identifier).filter { wanted[$0] == nil && !kept.contains($0) }
        var current: Set<String> = []
        for request in pending {
            guard let p = wanted[request.identifier] else { continue }
            if Self.matches(request, p) { current.insert(request.identifier) } else { stale.append(request.identifier) }
        }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for p in plan where !current.contains(Self.prefix + p.id) {
            try? await center.add(request(for: p))
        }
    }

    /// One request, on top of what is pending (used right after a meal is logged).
    func add(_ p: NotificationPlanner.Planned) async {
        try? await center.add(request(for: p))
    }

    private func request(for p: NotificationPlanner.Planned) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.body = p.body
        content.sound = .default
        content.threadIdentifier = p.threadId
        content.userInfo = ["route": p.route, "kind": p.kind.rawValue]
        content.categoryIdentifier = category(for: p.kind)
        let trigger = UNCalendarNotificationTrigger(dateMatching: Self.components(p.fireAt), repeats: false)
        return UNNotificationRequest(identifier: Self.prefix + p.id, content: content, trigger: trigger)
    }

    private static func components(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// Same moment, same words — nothing to redo.
    private static func matches(_ request: UNNotificationRequest, _ p: NotificationPlanner.Planned) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return false }
        let want = components(p.fireAt), have = trigger.dateComponents
        return have.year == want.year && have.month == want.month && have.day == want.day
            && have.hour == want.hour && have.minute == want.minute
            && request.content.title == p.title && request.content.body == p.body
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
        case .breakfast, .morningSnack, .lunch, .afternoonSnack, .dinner: Self.categoryMeal
        case .mealReaction: Self.categoryReaction
        case .weeklySummary, .wearableStale: ""
        }
    }
}
