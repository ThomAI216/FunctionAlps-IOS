import Foundation

/// The multi-moment check-in. The phone sends the RAW answers to ONE writer — RPC `member_submit_checkin` v2 —
/// which SCORES them (`checkin_energy_overall` / `checkin_sleep_overall`, the Expo `functional-engine` in SQL),
/// upserts the moment, recomputes the DAY SUMMARY from every moment of the day and appends the per-dimension
/// events in one transaction (PRD §41: scoring and roll-up live in the database, not in each client).
/// `CheckinEngine` stays as the tested reference of both, and still guards "nothing answered → nothing sent".
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

    /// Returns the moment as the SERVER scored it (+ the day's red flags), or nil when the member answered nothing at all.
    func save(slot: MomentSlot, answers: FunctionalAnswers, catalogPills: [String: [String]], note: String? = nil, patientId: String) async throws -> CheckinSubmitResult? {
        let submittedAt = now()
        let day = ISO8601.dayString(submittedAt, calendar: calendar)
        // The reference engine still builds the moment: it merges the pills, trims the note and is the content guard.
        let reference = CheckinEngine.momentFromAnswers(slot: slot, answers: answers, catalogPills: catalogPills, note: note, submittedAt: submittedAt)
        guard CheckinEngine.momentHasContent(reference) else { return nil }

        return try await backend.submitCheckin(day: day, slot: slot, submission: CheckinEngine.submission(from: reference, answers: answers))
    }
}
