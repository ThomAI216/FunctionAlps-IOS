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
    /// The domain seam, for screens that read a single server-computed object (Trends).
    let backend: any FunctionAlpsBackend

    init(environment: AppEnvironment, transport: any HTTPTransport, sessionStore: any SessionStore) {
        self.environment = environment
        let state = AppState()
        self.state = state

        let authClient = SupabaseAuthClient(environment: environment, transport: transport)
        let sessions = SessionManager(auth: authClient, store: sessionStore)
        let requester = AuthorizedRequester(sessions: sessions, transport: transport)
        let rest = PostgRESTClient(environment: environment, requester: requester)
        let functions = EdgeFunctionClient(environment: environment, requester: requester)
        let storage = StorageClient(environment: environment, requester: requester)
        let backend = SupabaseBackend(rest: rest, functions: functions, storage: storage)

        self.auth = AuthService(sessions: sessions, state: state)
        self.members = MemberService(sessions: sessions, backend: backend)
        self.dashboard = DashboardService(backend: backend)
        self.meals = MealService(backend: backend)
        self.checkins = CheckinService(backend: backend)
        self.library = LibraryService(backend: backend)
        self.backend = backend
    }

    /// Production wiring. Throws only on a misconfigured build (missing xcconfig values).
    static func live() throws -> AppDependencies {
        let environment = try AppEnvironment.fromBundle()
        return AppDependencies(environment: environment, transport: URLSessionTransport(), sessionStore: KeychainSessionStore())
    }

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
