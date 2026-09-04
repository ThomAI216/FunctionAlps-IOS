import SwiftUI
import UserNotifications

/// UIKit's two remaining jobs: the APNs device token and notification taps. Everything else is SwiftUI.
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
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let route = (info["route"] as? String).flatMap(URL.init(string:))
        await MainActor.run {
            if action == "fine", let route, let mealId = AppRouter.mealId(from: route) {
                // "Felt fine" from the reaction banner: rated without opening the app.
                Self.notifications?.quickFine(mealId: mealId)
                return
            }
            guard let route else { return }
            if let router = Self.router { router.open(route) } else { Self.pendingRoute = route }
        }
    }
}
