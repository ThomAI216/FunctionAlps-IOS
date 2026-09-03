import Foundation

/// The multi-moment check-in, mirroring `lib/checkin/moment-persistence.ts`:
/// the moment lands first (source of truth), the DAY SUMMARY is recomputed from every moment
/// of the day, and the per-dimension events are appended LAST — exactly once per save.
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

        try await backend.upsertCheckinMoment(patientId: patientId, day: day, moment: moment)

        // Recompute from every moment of the day (this one included); never regress on an empty read-back.
        let saved = try await backend.checkinMoments(patientId: patientId, day: day)
        let all = saved.isEmpty ? [moment] : saved

        // Read the day row FIRST — the felt prefill + no-wipe carry depend on it; a read failure aborts.
        let existing = try await backend.dailyCheckinCarry(patientId: patientId, day: day)
        let patch = CheckinEngine.daySummaryPatch(all, existing: existing, completedAt: submittedAt)
        try await backend.upsertDailySummary(patientId: patientId, day: day, patch: patch)

        try await backend.insertCheckinEvents(patientId: patientId, events: CheckinEngine.momentEvents(moment))
        return moment
    }
}
