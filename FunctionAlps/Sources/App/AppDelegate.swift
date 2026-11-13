import SwiftUI
import UserNotifications

/// UIKit's two remaining jobs: the APNs device token and notification taps. Everything else is SwiftUI.
///
/// The notification-centre callbacks are the COMPLETION-HANDLER forms, `nonisolated`, and hop to the main
/// queue themselves. The `async` forms crashed the app on a tap (build 24): the class is main-actor
/// (UIApplicationDelegate), UNUserNotificationCenter calls its delegate from its own queue, and the
/// Swift 6 async thunk trapped on the executor check before our code ran.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the App once dependencies exist.
    @MainActor static var notifications: NotificationService?
    /// Answers a supplement reminder's "Taken" / "Later" buttons.
    @MainActor static var supplements: SupplementService? {
        didSet { flushPendingSupplementActions() }
    }
    /// Buttons pressed before the app was ready (a cold start from the notification's action): replayed once it is.
    @MainActor private static var pendingSupplementActions: [(action: String, group: SupplementReminders.Group)] = []
    @MainActor static var router: AppRouter?
    /// A tap that arrived before the UI was ready (cold start from a notification).
    @MainActor static var pendingRoute: URL?
    /// The same for a push with no route: the notification row is read once the app is signed in.
    @MainActor static var pendingNotificationId: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Portrait everywhere, except while a library video is on screen (`PlayerOrientation`).
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        PlayerOrientation.mask
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in Self.notifications?.deviceTokenReceived(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.data.error("apns register failed: \(String(describing: error), privacy: .public)")
    }

    /// Foreground: show the banner too (a reminder that fires while the app is open is still useful).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// A tap (or an action button). Read what is needed on the calling queue, answer the centre at once,
    /// then route on the main queue — never inside the callback, and never before the UI exists.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let route = (info["route"] as? String).flatMap(URL.init(string:))
        let notificationId = info["notification_id"] as? String
        let supplementGroup = SupplementReminders.group(moment: info["moment"] as? String, day: info["day"] as? String, ids: info["ids"] as? String)
        completionHandler()
        Task { @MainActor in
            if let supplementGroup, action == LocalNotifications.actionSupplementTaken || action == LocalNotifications.actionSupplementLater {
                Self.handleSupplement(action: action, group: supplementGroup)
                return
            }
            Self.handle(action: action, route: route, notificationId: notificationId)
        }
    }

    /// "Taken" logs every supplement of the group without opening the app; "Later" asks again in half an hour.
    @MainActor
    private static func handleSupplement(action: String, group: SupplementReminders.Group) {
        guard let supplements else {
            pendingSupplementActions.append((action, group))
            return
        }
        Task { @MainActor in
            if action == LocalNotifications.actionSupplementTaken { await supplements.logTaken(group) } else { await supplements.snooze(group) }
        }
    }

    @MainActor
    private static func flushPendingSupplementActions() {
        guard supplements != nil, !pendingSupplementActions.isEmpty else { return }
        let waiting = pendingSupplementActions
        pendingSupplementActions = []
        for item in waiting { handleSupplement(action: item.action, group: item.group) }
    }

    @MainActor
    private static func handle(action: String, route: URL?, notificationId: String?) {
        if action == "fine", let route, let mealId = AppRouter.mealId(from: route) {
            // "Felt fine" from the reaction banner: rated without opening the app.
            notifications?.quickFine(mealId: mealId)
            return
        }
        if route == nil, let notificationId {
            // A row written without a route (CLINICAL's notifyPatient): its item says where it belongs.
            if let notifications, let router {
                Task { @MainActor in
                    if let url = await notifications.route(forNotification: notificationId) { router.open(url) }
                }
            } else {
                pendingNotificationId = notificationId
            }
            return
        }
        guard let route else { return }
        if let router {
            // One more turn of the run loop: the tap may land mid-transition (background → foreground),
            // and navigation state must not change while SwiftUI is still committing the last frame.
            Task { @MainActor in
                await Task.yield()
                router.open(route)
            }
        } else {
            pendingRoute = route
        }
    }
}
