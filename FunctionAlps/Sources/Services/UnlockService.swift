import Foundation
import Observation

/// The Foundation Track's unlocks (Thomas, 2026-11-06): Trends after 3 days in a row of using the app, Food with
/// the first meal (`TrackUnlocks`). Reads the member's last 30 days of check-ins and meals — the track is 14 days,
/// so a run of 3 is always inside — once per tab change and whenever the app comes forward.
///
/// Locks apply only to a member on the track (`TrackService.status` active); everyone else keeps every tab.
/// Fail-open: an unreadable history never locks a tab (a lock that cannot be explained must not stand).
@MainActor
@Observable
final class UnlockService {
    enum Phase: Equatable { case unknown, known }

    private(set) var phase: Phase = .unknown
    private(set) var trendsOpen = true
    private(set) var foodOpen = true
    /// Days in a row as of today (for "2 of 3").
    private(set) var streak = 0

    private let backend: any FunctionAlpsBackend
    private let members: MemberService?
    private let now: @Sendable () -> Date
    private let freshness: DataFreshness?
    private var refreshedAt: Date?
    private var refreshedVersion = 0
    private var isRefreshing = false

    /// A tab switch or a foreground inside this window re-uses what is held; a real write calls `refresh(force: true)`.
    static let staleAfter: TimeInterval = 60

    init(backend: any FunctionAlpsBackend, members: MemberService? = nil, freshness: DataFreshness? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.freshness = freshness
        self.backend = backend
        self.members = members
        self.now = now
    }

    /// Sign-out: forget the previous member's unlocks so the next member never inherits them.
    func reset() {
        phase = .unknown
        trendsOpen = true
        foodOpen = true
        streak = 0
        refreshedAt = nil
        refreshedVersion = 0
    }

    func refresh(force: Bool = false) async {
        guard force || !isRefreshing else { return }
        let version = freshness?.homeVersion ?? 0   // a check-in or meal since the last read moves it
        if !force, phase == .known, version == refreshedVersion, let refreshedAt, now().timeIntervalSince(refreshedAt) < Self.staleAfter { return }
        isRefreshing = true
        defer { isRefreshing = false; refreshedAt = now(); refreshedVersion = version }
        do {
            guard let patientId = try await MemberService.patientId(via: members, backend: backend) else { phase = .known; return }
            let since = Calendar.current.date(byAdding: .day, value: -30, to: now()) ?? now()
            async let meals = backend.meals(patientId: patientId, since: since)
            async let checkins = backend.dailyCheckins(patientId: patientId, since: ISO8601.dayString(since))
            let (m, c) = try await (meals, checkins)
            let days = TrackUnlocks.activeDays(checkins: c, mealDates: m.map(\.loggedAt))
            trendsOpen = TrackUnlocks.trendsOpen(days)
            foodOpen = TrackUnlocks.foodOpen(mealCount: m.count)
            streak = TrackUnlocks.currentRun(days, today: ISO8601.dayString(now()))
        } catch {
            if let app = error as? AppError, app == .forbidden || app == .unauthorized { await members?.invalidate() }
            trendsOpen = true
            foodOpen = true
        }
        phase = .known
    }
}
