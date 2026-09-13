import Foundation

/// The multi-moment check-in. The phone scores the moment (`CheckinEngine`, the Expo `functional-engine`
/// line for line) and hands it to ONE writer — RPC `member_submit_checkin` — which upserts it, recomputes the
/// DAY SUMMARY from every moment of the day and appends the per-dimension events in one transaction
/// (PRD §41: the roll-up lives in the database, not in each client). `CheckinEngine.daySummaryPatch` stays
/// as the tested reference of that roll-up.
struct CheckinService: Sendable {
    private let backend: any FunctionAlpsBackend
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(backend: any FunctionAlpsBackend, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.calendar = calendar
        self.now = now
    }

    var today: String { ISO8601.dayString(now(), calendar: calendar) }
    var currentSlot: MomentSlot { MomentSlot.current(hour: calendar.component(.hour, from: now())) }

    func todayMoments(patientId: String) async throws -> [CheckinMoment] {
        try await backend.checkinMoments(patientId: patientId, day: today)
    }

    /// Returns the saved moment, or nil when the member answered nothing at all.
    func save(slot: MomentSlot, answers: FunctionalAnswers, catalogPills: [String: [String]], note: String? = nil, patientId: String) async throws -> CheckinMoment? {
        let submittedAt = now()
        let day = ISO8601.dayString(submittedAt, calendar: calendar)
        let moment = CheckinEngine.momentFromAnswers(slot: slot, answers: answers, catalogPills: catalogPills, note: note, submittedAt: submittedAt)
        guard CheckinEngine.momentHasContent(moment) else { return nil }

        try await backend.submitCheckin(day: day, slot: slot, moment: moment)
        return moment
    }
}
