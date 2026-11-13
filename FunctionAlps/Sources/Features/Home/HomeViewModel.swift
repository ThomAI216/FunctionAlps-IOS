import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    struct Content: Sendable, Equatable {
        let member: Member
        let today: TodaySnapshot
        /// Items the practice sent with a message and the member has not opened (the Home nudge). 0 = no card.
        var newResources: Int = 0
        /// Who the member talks to and the thread's last message (the Home messages card); both fail soft to none.
        var careTeam: CareTeam = .empty
        var lastMessage: PatientMessage? = nil
    }

    enum Blocker: Equatable { case notRegistered }

    var state: Loadable<Content> = .loading
    var blocker: Blocker?
    private(set) var isRefreshing = false
    /// The server-computed scores, read after the first paint (an edge function; Home never waits on it). Nil until read, or when unreachable.
    private(set) var scores: MemberScores?
    private(set) var scoresLoading = false

    /// A re-appearing Home re-reads only when what it holds is older than this (like `TrendsService.staleAfter`).
    static let staleAfter: TimeInterval = 60
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var loadedVersion = 0
    @ObservationIgnored private var scoresTask: Task<Void, Never>?

    private let members: MemberService
    private let dashboard: DashboardService
    private let auth: AuthService
    private let messaging: MessagingService?
    private let freshness: DataFreshness?
    private let now: @Sendable () -> Date

    init(members: MemberService, dashboard: DashboardService, auth: AuthService, messaging: MessagingService? = nil,
         freshness: DataFreshness? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.freshness = freshness
        self.now = now
        self.members = members
        self.dashboard = dashboard
        self.auth = auth
        self.messaging = messaging
    }

    /// Nothing loaded yet, older than `staleAfter`, or a write Home shows happened since the last read.
    var isStale: Bool {
        guard let loadedAt else { return true }
        return now().timeIntervalSince(loadedAt) > Self.staleAfter || (freshness?.homeVersion ?? 0) != loadedVersion
    }

    /// Back on Home with data already on screen: re-read only when stale. Pull-to-refresh and retries call `load` directly.
    func loadIfStale() async {
        guard state.value != nil, isStale else { return }
        await load(refresh: true)
    }

    func load(refresh: Bool = false, force: Bool = false) async {
        if refresh { isRefreshing = true } else if state.value == nil { state = .loading }
        defer { isRefreshing = false }
        let versionAtStart = freshness?.homeVersion ?? 0   // a write that lands mid-read keeps Home stale
        do {
            let member = try await members.currentMember(forceRefresh: force)
            // The nudge rides its own read and fails soft to 0: Home never waits on it.
            async let fresh = messaging?.unopenedSentCount() ?? 0
            async let team = messaging?.careTeam() ?? .empty
            async let last = messaging?.lastMessage()
            let today = try await dashboard.today(patientId: member.patientId)
            blocker = nil
            state = .loaded(Content(member: member, today: today, newResources: await fresh, careTeam: await team, lastMessage: await last))
            loadedAt = now()
            loadedVersion = versionAtStart
            loadScores()
        } catch MemberService.MemberError.notRegistered {
            blocker = .notRegistered
            state = .empty
        } catch let error as AppError {
            Log.error(error, in: Log.data, context: "home.load")
            if case .unauthorized = error { await auth.handleUnauthorized(); return }
            if state.value == nil { state = .failed(error) }
        } catch {
            Log.data.error("home.load: \(String(describing: error), privacy: .public)")
            if state.value == nil { state = .failed(.unknown(detail: String(describing: error))) }
        }
    }

    /// The scores fill in after the first paint, with their own loading flag; a failure leaves them nil.
    private func loadScores() {
        scoresTask?.cancel()
        scoresLoading = true
        let dashboard = self.dashboard
        scoresTask = Task { [weak self] in
            let read = await dashboard.scores()
            guard !Task.isCancelled, let self else { return }
            self.scores = read ?? self.scores
            self.scoresLoading = false
        }
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return String(localized: "home.greeting.morning", defaultValue: "Good morning")
        case 12..<18: return String(localized: "home.greeting.afternoon", defaultValue: "Good afternoon")
        default: return String(localized: "home.greeting.evening", defaultValue: "Good evening")
        }
    }
}
