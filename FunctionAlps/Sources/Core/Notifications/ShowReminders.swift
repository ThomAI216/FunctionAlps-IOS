import Foundation
import UserNotifications

/// "Remind me every day" for a show experiment: one local notification per remaining day (the plan is
/// `ShowLogic.reminderPlan`), tapped → the episode. Same centre and permission flow as the check-in reminders
/// (`NotificationService.askIfNeeded`), but a DIFFERENT id prefix: `LocalNotifications.apply` replaces every pending
/// `fa.` request with the day's plan, and must never wipe these.
@MainActor
final class ShowReminders {
    static let prefix = "show.exp."

    struct Item: Sendable, Equatable {
        let day: Int
        let fireAt: Date
        let title: String
        let body: String
    }

    private let center = UNUserNotificationCenter.current()

    private static func idPrefix(_ slug: String) -> String { "\(prefix)\(slug)." }

    /// On = at least one reminder of this experiment is still pending.
    func isOn(slug: String) async -> Bool {
        let p = Self.idPrefix(slug)
        return await center.pendingNotificationRequests().contains { $0.identifier.hasPrefix(p) }
    }

    func disable(slug: String) async {
        let p = Self.idPrefix(slug)
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(p) }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }

    /// Replaces this experiment's pending reminders with `items`.
    func apply(slug: String, items: [Item]) async {
        await disable(slug: slug)
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = "show.\(slug)"
            content.userInfo = ["route": "functionalps://library/show/\(slug)", "kind": "show.experiment"]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireAt)
            let request = UNNotificationRequest(identifier: "\(Self.idPrefix(slug))\(item.day)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(request)
        }
    }
}
