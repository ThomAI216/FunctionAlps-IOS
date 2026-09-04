import SwiftUI

@main
struct FunctionAlpsApp: App {
    /// APNs token + notification taps (UIKit's two remaining jobs).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var dependencies: AppDependencies?
    @State private var configurationError: String?

    init() {
        do {
            let live = try AppDependencies.live()
            _dependencies = State(initialValue: live)
            // HealthKit background delivery must be re-armed at every launch (iOS wakes the app for new samples).
            let wearables = live.wearables
            Task { @MainActor in await wearables.armBackgroundDeliveryIfConnected() }
        } catch {
            _configurationError = State(initialValue: String(describing: error))
        }
    }

    var body: some Scene {
        WindowGroup {
            if let dependencies {
                RootView()
                    .environment(dependencies)
                    .environment(dependencies.state)
                    .tint(FAColor.brand)
            } else {
                // A build with missing xcconfig values must fail loudly, never ship half-configured.
                FAErrorState(
                    title: "Configuration error",
                    message: configurationError ?? "Unknown",
                    retryTitle: nil,
                    retry: nil
                )
            }
        }
    }
}
