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

    /// The day before today, `YYYY-MM-DD` (the RPC takes today and yesterday, patient-local).
    var yesterday: String { CheckinDayLabel.previousDay(of: today, calendar: calendar) ?? today }

    func todayMoments(patientId: String) async throws -> [CheckinMoment] {
        try await backend.checkinMoments(patientId: patientId, day: today)
    }

    func moments(patientId: String, day: String) async throws -> [CheckinMoment] {
        try await backend.checkinMoments(patientId: patientId, day: day)
    }

    /// The day row (what the day holds as a whole — a wearable may have given it a night the check-in never saw).
    func dailyCheckin(patientId: String, day: String) async throws -> DailyCheckin? {
        try await backend.dailyCheckin(patientId: patientId, day: day)
    }

    /// "Feeling for the day" — nil when none was saved for `day`.
    func dayFeeling(patientId: String, day: String) async throws -> DayFeeling? {
        try await backend.dayFeeling(patientId: patientId, day: day)
    }

    func saveDayFeeling(_ feeling: DayFeeling, patientId: String) async throws {
        try await backend.saveDayFeeling(patientId: patientId, feeling: feeling)
    }

    /// Returns the moment as the SERVER scored it (+ the day's red flags), or nil when the member answered nothing at all.
    /// `day` is today unless a missed day is being caught up (the RPC accepts today and yesterday).
    func save(slot: MomentSlot, answers: FunctionalAnswers, catalogPills: [String: [String]], note: String? = nil, patientId: String, day requestedDay: String? = nil) async throws -> CheckinSubmitResult? {
        let submittedAt = now()
        let day = requestedDay ?? ISO8601.dayString(submittedAt, calendar: calendar)
        // The reference engine still builds the moment: it merges the pills, trims the note and is the content guard.
        let reference = CheckinEngine.momentFromAnswers(slot: slot, answers: answers, catalogPills: catalogPills, note: note, submittedAt: submittedAt)
        guard CheckinEngine.momentHasContent(reference) else { return nil }

        return try await backend.submitCheckin(day: day, slot: slot, submission: CheckinEngine.submission(from: reference, answers: answers))
    }

    /// Last night is ONE answer: the MORNING slot's moment is its single source of truth, whichever check-in the member was
    /// in when they set it. `member_submit_checkin` upserts the WHOLE slot row (every column is overwritten), so this
    /// submission starts from what the morning moment already holds — marker answers, pills, note — and replaces only the
    /// sleep: nothing the member answered in an earlier version of the morning is wiped.
    func saveSleep(_ sleep: DimAnswers, existingMorning: CheckinMoment?, patientId: String, day: String? = nil) async throws -> CheckinSubmitResult? {
        let merged = Self.sleepSubmission(sleep: sleep, existingMorning: existingMorning)
        return try await save(slot: .morning, answers: merged.answers, catalogPills: merged.catalogPills, note: merged.note, patientId: patientId, day: day)
    }

    /// The morning slot's answers with `sleep` swapped in (pure — the part worth testing).
    static func sleepSubmission(sleep: DimAnswers, existingMorning: CheckinMoment?) -> (answers: FunctionalAnswers, catalogPills: [String: [String]], note: String?) {
        var answers = CheckinEngine.answersFromMoment(existingMorning)
        answers[.sleep] = sleep
        return (answers, CheckinEngine.catalogPills(from: existingMorning), existingMorning?.note)
    }

    /// The daily (evening-slot) answers WITHOUT sleep: the daily payload never carries its own copy of the night, so the
    /// two check-ins can never disagree (the morning slot owns it).
    static func withoutSleep(_ answers: FunctionalAnswers) -> FunctionalAnswers {
        var out = answers
        out[.sleep] = .empty
        return out
    }
}
