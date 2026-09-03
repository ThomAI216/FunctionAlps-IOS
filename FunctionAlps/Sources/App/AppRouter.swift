import SwiftUI

/// Type-safe navigation routes. Each tab owns a `NavigationStack` bound to one path.
enum Route: Hashable {
    case profile
    case settings
}

@MainActor
@Observable
final class AppRouter {
    var homePath: [Route] = []
    var profilePath: [Route] = []

    enum Tab: Hashable { case home, profile }
    var tab: Tab = .home
}

struct MainTabView: View {
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.homePath) {
                HomeView()
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tabItem { Label(String(localized: "tab.today", defaultValue: "Today"), systemImage: "sun.max") }
            .tag(AppRouter.Tab.home)

            NavigationStack(path: $router.profilePath) {
                ProfileView()
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tabItem { Label(String(localized: "tab.profile", defaultValue: "Profile"), systemImage: "person.crop.circle") }
            .tag(AppRouter.Tab.profile)
        }
        .environment(router)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .profile: ProfileView()
        case .settings: SettingsView()
        }
    }
}
