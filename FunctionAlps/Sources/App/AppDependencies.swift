import Foundation
import Observation

/// Composition root. Built once at launch; injected with `.environment(...)`.
/// Every feature receives explicit services — no global singletons (PRD §16).
@MainActor
@Observable
final class AppDependencies {
    let environment: AppEnvironment
    let state: AppState
    let auth: AuthService
    let members: MemberService
    let dashboard: DashboardService
    let meals: MealService
    let checkins: CheckinService
    let library: LibraryService
    let profile: ProfileService
    let messaging: MessagingService
    let account: AccountService
    let wearables: WearableService
    let notifications: NotificationService
    let gut: GutService
    let protocols: ProtocolService
    /// Today's focus — shared, so the check-in screen's recomputation lands on the Home card.
    let focus: FocusService
    /// Released lab results — shared, so the list, the result and the marker sheet read one load.
    let labs: LabResultsService
    /// The clinician's habits for today, with the check-off.
    let habits: HabitsService
    /// The Foundation Track (the 14-day start): status, days, questionnaires, answers and ticks — shared by Home's
    /// card, the questionnaire flow and the reminder plan.
    let track: TrackService
    /// The domain seam, for screens that read a single server-computed object (Trends).
    let backend: any FunctionAlpsBackend

    init(environment: AppEnvironment, transport: any HTTPTransport, sessionStore: any SessionStore, backendOverride: (any FunctionAlpsBackend)? = nil) {
        self.environment = environment
        let state = AppState()
        self.state = state

        let authClient = SupabaseAuthClient(environment: environment, transport: transport)
        let sessions = SessionManager(auth: authClient, store: sessionStore)
        let requester = AuthorizedRequester(sessions: sessions, transport: transport)
        let rest = PostgRESTClient(environment: environment, requester: requester)
        let functions = EdgeFunctionClient(environment: environment, requester: requester)
        let storage = StorageClient(environment: environment, requester: requester)
        let backend: any FunctionAlpsBackend = backendOverride
            ?? SupabaseBackend(rest: rest, functions: functions, storage: storage, realtime: RealtimeClient(environment: environment, sessions: sessions))

        let auth = AuthService(sessions: sessions, state: state)
        self.auth = auth
        let members = MemberService(sessions: sessions, backend: backend)
        self.members = members
        self.dashboard = DashboardService(backend: backend)
        self.meals = MealService(backend: backend)
        self.checkins = CheckinService(backend: backend)
        self.library = LibraryService(backend: backend)
        self.profile = ProfileService(backend: backend)
        self.messaging = MessagingService(backend: backend)
        self.account = AccountService(backend: backend)
        self.wearables = WearableService(backend: backend)
        self.notifications = NotificationService(backend: backend)
        self.gut = GutService(backend: backend)
        self.protocols = ProtocolService(backend: backend)
        self.focus = FocusService(backend: backend, auth: auth)
        self.labs = LabResultsService(backend: backend, members: members, auth: auth)
        self.habits = HabitsService(backend: backend, auth: auth)
        self.track = TrackService(backend: backend, auth: auth)
        self.backend = backend
    }

    /// Production wiring. Throws only on a misconfigured build (missing xcconfig values).
    static func live() throws -> AppDependencies {
        let environment = try AppEnvironment.fromBundle()
        return AppDependencies(environment: environment, transport: URLSessionTransport(), sessionStore: KeychainSessionStore())
    }

    #if DEBUG
    /// The showcase screenshots (Debug only): signed in as the sample member, every call answered by
    /// `ShowcaseBackend` — no network, no CM OS. See `Showcase`.
    static func showcase() -> AppDependencies {
        let environment = AppEnvironment(name: .development, supabaseURL: URL(string: "https://showcase.invalid")!,
                                         supabasePublishableKey: "showcase", apiBaseURL: nil)
        let store = InMemorySessionStore(session: AuthSession(
            accessToken: "showcase", refreshToken: "showcase", expiresAt: .distantFuture,
            userId: ShowcaseData.userId, email: "marie@example.com", patientId: ShowcaseData.patientId, displayName: "Marie"
        ))
        return AppDependencies(environment: environment, transport: PreviewTransport(), sessionStore: store, backendOverride: ShowcaseBackend())
    }
    #endif

    /// Preview/test wiring: in-memory session, no network.
    static func preview(signedIn: Bool = true) -> AppDependencies {
        let environment = AppEnvironment(
            name: .development,
            supabaseURL: URL(string: "https://preview.invalid")!,
            supabasePublishableKey: "preview",
            apiBaseURL: nil
        )
        let store = InMemorySessionStore(session: signedIn ? AuthSession(
            accessToken: "preview", refreshToken: "preview", expiresAt: .distantFuture,
            userId: "00000000-0000-0000-0000-000000000000", email: "preview@functionalps.ch",
            patientId: "11111111-1111-1111-1111-111111111111", displayName: "Alex Preview"
        ) : nil)
        return AppDependencies(environment: environment, transport: PreviewTransport(), sessionStore: store)
    }
}

/// Serves canned rows so SwiftUI previews render without a backend.
struct PreviewTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(status: 200, headers: [:], body: Data("[]".utf8))
    }
}
