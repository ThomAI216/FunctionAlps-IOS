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
    @MainActor static var router: AppRouter?
    /// A tap that arrived before the UI was ready (cold start from a notification).
    @MainActor static var pendingRoute: URL?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
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
        let route = (response.notification.request.content.userInfo["route"] as? String).flatMap(URL.init(string:))
        completionHandler()
        Task { @MainActor in Self.handle(action: action, route: route) }
    }

    @MainActor
    private static func handle(action: String, route: URL?) {
        if action == "fine", let route, let mealId = AppRouter.mealId(from: route) {
            // "Felt fine" from the reaction banner: rated without opening the app.
            notifications?.quickFine(mealId: mealId)
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
