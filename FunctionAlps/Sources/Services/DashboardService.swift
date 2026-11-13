import Foundation

/// Assembles the Home snapshot for the member's local calendar day.
struct DashboardService: Sendable {
    private let backend: any FunctionAlpsBackend
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(backend: any FunctionAlpsBackend, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.calendar = calendar
        self.now = now
    }

    /// The fast reads only. The server-computed scores ride `scores()` instead: `member-scores` is an edge function
    /// (cold starts), and Home's first paint must not wait for it. `TodaySnapshot.scores` is left nil here.
    func today(patientId: String) async throws -> TodaySnapshot {
        let current = now()
        let day = ISO8601.dayString(current, calendar: calendar)
        let startOfDay = calendar.startOfDay(for: current)
        async let meals = backend.meals(patientId: patientId, since: startOfDay)
        async let checkin = backend.dailyCheckin(patientId: patientId, day: day)
        async let unread = backend.unreadClinicianMessageCount(patientId: patientId)
        async let moments = backend.checkinMoments(patientId: patientId, day: day)
        let since = ISO8601.dayString(calendar.date(byAdding: .day, value: -13, to: current) ?? current, calendar: calendar)
        async let history = backend.dailyCheckins(patientId: patientId, since: since)
        // Best-effort too: a failed read of the day feeling means "not done", never a blank Home.
        async let feelingSaved: Bool = { ((try? await backend.dayFeeling(patientId: patientId, day: day)) ?? nil) != nil }()
        return try await TodaySnapshot(day: day, meals: meals, checkin: checkin, unreadClinicianMessages: unread, moments: moments, history: history, dayFeelingSaved: feelingSaved)
    }

    /// Best-effort: a scoring hiccup must never blank Home, so a failure is nil.
    func scores() async -> MemberScores? {
        let current = now()
        return try? await backend.memberScores(tzOffsetMinutes: calendar.timeZone.secondsFromGMT(for: current) / 60)
    }
}
