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

    func today(patientId: String) async throws -> TodaySnapshot {
        let current = now()
        let day = ISO8601.dayString(current, calendar: calendar)
        let startOfDay = calendar.startOfDay(for: current)
        async let meals = backend.meals(patientId: patientId, since: startOfDay)
        async let checkin = backend.dailyCheckin(patientId: patientId, day: day)
        async let unread = backend.unreadClinicianMessageCount(patientId: patientId)
        return try await TodaySnapshot(day: day, meals: meals, checkin: checkin, unreadClinicianMessages: unread)
    }
}
