import SwiftUI

@main
struct FunctionAlpsApp: App {
    @State private var dependencies: AppDependencies?
    @State private var configurationError: String?

    init() {
        do {
            _dependencies = State(initialValue: try AppDependencies.live())
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
