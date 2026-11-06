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
    private let now: @Sendable () -> Date

    init(backend: any FunctionAlpsBackend, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.now = now
    }

    func refresh() async {
        do {
            guard let patientId = try await backend.currentPatientId() else { phase = .known; return }
            let since = Calendar.current.date(byAdding: .day, value: -30, to: now()) ?? now()
            async let meals = backend.meals(patientId: patientId, since: since)
            async let checkins = backend.dailyCheckins(patientId: patientId, since: ISO8601.dayString(since))
            let (m, c) = try await (meals, checkins)
            let days = TrackUnlocks.activeDays(checkins: c, mealDates: m.map(\.loggedAt))
            trendsOpen = TrackUnlocks.trendsOpen(days)
            foodOpen = TrackUnlocks.foodOpen(mealCount: m.count)
            streak = TrackUnlocks.currentRun(days, today: ISO8601.dayString(now()))
        } catch {
            trendsOpen = true
            foodOpen = true
        }
        phase = .known
    }
}
