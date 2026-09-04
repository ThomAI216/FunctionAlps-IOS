import SwiftUI

/// Type-safe navigation routes. Each tab owns a `NavigationStack` bound to one path.
enum Route: Hashable {
    case profile
    case settings
    case meal(String)
    case checkin(MomentSlot)
    case track(String)
    case read(String)
    // Profile tab subpages (the Expo `(screens)/profile-*`, `guide`, `privacy-*`, `legal/*`)
    case carePlan
    case baseline
    case feedback
    case guide
    case guideChapter(String)
    case privacy
    case consents
    case viewData
    case legal(String)
    case messages
    case help
    case wearables
}

@MainActor
@Observable
final class AppRouter {
    var homePath: [Route] = []
    var trendsPath: [Route] = []
    var foodPath: [Route] = []
    var libraryPath: [Route] = []
    var profilePath: [Route] = []

    /// The web app's five tabs, in its order.
    enum Tab: Hashable, CaseIterable { case home, trends, food, library, profile }
    var tab: Tab = .home

    /// The reader replaces the floating navbar with its own mark-done bar.
    var hidesTabBar: Bool {
        if case .read = libraryPath.last { return true }
        return false
    }
}

/// Five stacks behind one floating glass pill (the system tab bar is hidden on every root).
struct MainTabView: View {
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.homePath) {
                HomeView()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.home)

            NavigationStack(path: $router.trendsPath) {
                TrendsView()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.trends)

            NavigationStack(path: $router.foodPath) {
                FoodView()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.food)

            NavigationStack(path: $router.libraryPath) {
                LibraryView()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.library)

            NavigationStack(path: $router.profilePath) {
                ProfileView()
                    .faSwipeBack()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tag(AppRouter.Tab.profile)
        }
        .tint(FAColor.brand)
        .overlay(alignment: .bottom) {
            if !router.hidesTabBar {
                FloatingTabBar(selection: $router.tab)
                    .padding(.bottom, 2)
            }
        }
        .environment(router)
    }

    private func destination(_ route: Route) -> some View {
        screen(route).faSwipeBack()
    }

    @ViewBuilder
    private func screen(_ route: Route) -> some View {
        switch route {
        case .profile: ProfileView()
        case .settings: SettingsView()
        case .meal(let id): MealDetailView(mealId: id)
        case .checkin(let slot): CheckinMomentView(slot: slot)
        case .track(let slug): TrackView(slug: slug)
        case .read(let slug): ReaderView(slug: slug)
        case .carePlan: CarePlanView()
        case .baseline: BaselineEditView()
        case .feedback: FeedbackView()
        case .guide: GuideView()
        case .guideChapter(let key): GuideChapterView(key: key)
        case .privacy: PrivacyView()
        case .consents: ConsentsView()
        case .viewData: ViewDataView()
        case .legal(let key): LegalDocumentView(key: key)
        case .messages: MessagesView()
        case .help: HelpView()
        case .wearables: WearablesView()
        }
    }
}
