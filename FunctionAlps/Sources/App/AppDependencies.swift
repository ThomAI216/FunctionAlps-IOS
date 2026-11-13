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
    /// Bumped by the write paths Home's snapshot reflects; Home reloads on re-appear when it moved or went stale.
    let freshness: DataFreshness
    let dashboard: DashboardService
    let meals: MealService
    let checkins: CheckinService
    let library: LibraryService
    /// "The FunctionAlps Show" in the Library (CLINICAL library API + experiment progress).
    let shows: ShowService
    let profile: ProfileService
    let messaging: MessagingService
    let account: AccountService
    let wearables: WearableService
    let notifications: NotificationService
    /// The member's supplements: Home's card, the Plan's list, each supplement's page and the grouped reminders.
    let supplements: SupplementService
    let gut: GutService
    let protocols: ProtocolService
    /// Today's focus — shared, so the check-in screen's recomputation lands on the Home card.
    let focus: FocusService
    /// Released lab results — shared, so the list, the result and the marker sheet read one load.
    let labs: LabResultsService
    /// The member's released documents, and whether a draft plan is being prepared.
    let documents: DocumentsService
    /// The clinician's habits for today, with the check-off.
    let habits: HabitsService
    /// The client's care plan as the practice shared it (programmes, objectives, wins, complaints, hypotheses) —
    /// shared by Today's card, the Plan page and its screens.
    let clientPlan: ClientCarePlanService
    /// The Foundation Track (the 14-day start): status, days, questionnaires, answers and ticks — shared by Home's
    /// card, the questionnaire flow and the reminder plan.
    let track: TrackService
    /// What the track unlocks by use: Trends after 3 days in a row, Food with the first meal.
    let unlocks: UnlockService
    /// The Trends tab and its detail pages: one shared read of the member's own logs, with the window they chose.
    let trends: TrendsService
    /// The practice's signal explanations (`signal_explanations`), read once per launch; no content = the blocks stay hidden.
    let signals: SignalContentService
    /// The domain seam, for screens that read a single server-computed object.
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
        let clinical = environment.clinicalAPIURL.map { ClinicalAPIClient(baseURL: $0, sessions: sessions, transport: transport) }
        let backend: any FunctionAlpsBackend = backendOverride
            ?? SupabaseBackend(rest: rest, functions: functions, storage: storage, realtime: RealtimeClient(environment: environment, sessions: sessions),
                               clinical: clinical)

        let freshness = DataFreshness()
        self.freshness = freshness
        let auth = AuthService(sessions: sessions, state: state)
        self.auth = auth
        let members = MemberService(sessions: sessions, backend: backend)
        self.members = members
        self.dashboard = DashboardService(backend: backend)
        self.meals = MealService(backend: backend, freshness: freshness)
        self.checkins = CheckinService(backend: backend, freshness: freshness)
        self.library = LibraryService(backend: backend)
        self.shows = ShowService(backend: backend)
        self.profile = ProfileService(backend: backend, members: members)
        self.messaging = MessagingService(backend: backend, members: members)
        self.account = AccountService(backend: backend)
        let wearables = WearableService(backend: backend)
        self.wearables = wearables
        let notifications = NotificationService(backend: backend)
        self.notifications = notifications
        self.supplements = SupplementService(backend: backend, auth: auth, notifications: notifications)
        self.gut = GutService(backend: backend)
        self.protocols = ProtocolService(backend: backend)
        self.focus = FocusService(backend: backend, auth: auth)
        self.labs = LabResultsService(backend: backend, members: members, auth: auth)
        self.documents = DocumentsService(backend: backend, members: members, auth: auth)
        self.habits = HabitsService(backend: backend, auth: auth)
        self.clientPlan = ClientCarePlanService(backend: backend, members: members, auth: auth)
        self.track = TrackService(backend: backend, auth: auth, members: members)
        let unlocks = UnlockService(backend: backend, members: members, freshness: freshness)
        self.unlocks = unlocks
        let trends = TrendsService(backend: backend, auth: auth, wearables: wearables, members: members)
        self.trends = trends
        self.signals = SignalContentService(backend: backend)
        self.backend = backend
        // A session that ends (sign-out, dead token) drops everything cached for that member.
        auth.onSessionEnded = { [members, unlocks, trends] in
            await members.invalidate()
            await unlocks.reset()
            await trends.reset()
        }
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
