import Foundation

/// The four backend operations the Stress track needs — the member's OWN rows, under
/// RLS, with the member's own session.
///
/// Declared here, rather than added to `FunctionAlpsBackend`, so the drafts compile on
/// their own and the two test doubles that implement `FunctionAlpsBackend`
/// (`StubBackend`, `RecordingBackend`) do not have to grow four stubs. Wiring (brief
/// §9, step 2) makes `SupabaseBackend` conform, in `SupabaseBackend.swift` itself so
/// the private `rest` client is reachable.
protocol StressTrackBackend: Sendable {
    /// `pillar_assessment` — `pillar = 'stress'`, `status = 'active'`, at most one
    /// (the partial unique index `pillar_assessment_one_active` guarantees it).
    func activeStressAssessment(patientId: String) async throws -> StressAssessmentRow?
    /// `stress_diary_day` for one local date of one assessment, or nil.
    func stressDiaryDay(patientId: String, assessmentId: String, localDate: String) async throws -> StressDiaryDay?
    /// Upsert on `(patient_id, assessment_id, local_date)`. Throws on refusal — an RLS
    /// refusal (window closed, assessment not active) arrives as `AppError.forbidden`.
    func upsertStressDiaryDay(_ write: StressDiaryWrite) async throws
    /// Two answer keys of the member's own L1 response, for the S7 gate. Nil when none.
    func stressQuestionnaireWork(assessmentId: String) async throws -> StressQuestionnaireWorkRow?
}

/// Everything the check-in screen needs to show the additions for one moment.
/// Nil from `StressTrackService.load` means: show the check-in exactly as it is today.
struct StressCheckinContext: Sendable, Equatable {
    let window: StressTrackWindow
    let part: StressDiaryPart
    /// 1-based, for "Day 6 of 14".
    let dayNumber: Int
    /// S7's switch-off question can show on an obligation day (`StressWorkGate`). It
    /// never hides S7's day-type chip, which every member is asked.
    let showsWorkDetachment: Bool
    /// The day as it was loaded: the prefill, and the baseline a save compares against.
    let original: StressCheckinDraft

    /// The window's own length (`StressTrackWindow.dayCount`), never `protocolDays`
    /// alone — the two differ when the planned end does.
    var totalDays: Int { window.dayCount }

    /// The context once `draft` has been WRITTEN: it becomes the baseline.
    ///
    /// The one Save writes the track first and the check-in second. When the check-in
    /// fails, the member edits and saves again — and against the pre-save baseline an
    /// answer changed back to what was first loaded would read as "unchanged" and never
    /// be sent, while the row still holds what the first save wrote. It also stops the
    /// retry re-stamping `logged_via` / `logged_at`. The caller replaces only the
    /// context, never the draft the member is editing.
    func rebased(on draft: StressCheckinDraft) -> StressCheckinContext {
        var saved = draft
        saved.existedOnServer = true
        saved.lastUpdatedVia = StressDiaryWrite.via
        saved.lastUpdatedAt = nil
        return StressCheckinContext(window: window, part: part, dayNumber: dayNumber, showsWorkDetachment: showsWorkDetachment, original: saved)
    }
}

enum StressSaveOutcome: Sendable, Equatable {
    case saved
    /// Nothing in this half changed from what was loaded (including "nothing answered,
    /// nothing stored"). No request was made.
    case nothingToSave
    /// Today is outside the window — the track ended while the screen was open. No
    /// request was made. The caller must SAY so (brief §9 step 4) rather than drop the
    /// member's answers silently; the check-in itself is unaffected.
    case windowClosed
}

/// The Stress track's side of a check-in moment: whether to show the additions, what
/// to prefill them with, and the one write. Same shape as `CheckinService` and
/// `GutService` — a `Sendable` struct over the backend, with an injectable clock.
///
/// It computes no metric and decides no flag. It never touches `patient_checkin_moments`:
/// the check-in's own save is `CheckinService`'s, unchanged.
struct StressTrackService: Sendable {
    private let backend: any StressTrackBackend
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(backend: any StressTrackBackend, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.calendar = calendar
        self.now = now
    }

    /// The member's local date — computed EXACTLY as `CheckinService.today` computes
    /// the check-in's `checkin_date`, because the server joins this row to the day's
    /// evening and morning moments on it. Same function, same calendar, same clock.
    var today: String { ISO8601.dayString(now(), calendar: calendar) }

    /// Nil — show nothing extra — unless every one of these holds: the moment is
    /// morning or evening; the member has an ACTIVE STRESS assessment; today is inside
    /// its window. Throws when a read fails, and the caller then shows nothing extra
    /// either: a track that cannot be read must never block, or clobber, anything.
    func load(patientId: String, slot: MomentSlot) async throws -> StressCheckinContext? {
        guard let part = StressDiaryPart(slot: slot) else { return nil }
        guard let row = try await backend.activeStressAssessment(patientId: patientId),
              let window = StressTrackWindow(row: row) else { return nil }
        let day = today
        guard let dayNumber = window.dayNumber(on: day) else { return nil }

        // The prefill is not optional. Without it, a half answered on the web would
        // look blank here, and the first tap would overwrite it.
        let existing = try await backend.stressDiaryDay(patientId: patientId, assessmentId: window.assessmentId, localDate: day)
        // The switch-off gate is optional, and fails open (see StressWorkGate). It is
        // only about work: the day-type chip shows either way.
        let questionnaire = try? await backend.stressQuestionnaireWork(assessmentId: window.assessmentId)

        return StressCheckinContext(
            window: window,
            part: part,
            dayNumber: dayNumber,
            showsWorkDetachment: StressWorkGate.showsWorkDetachment(questionnaire),
            // The prefill carries the stored day_type, so a day typed on the web shows
            // its chip here and a save does not clear it.
            original: existing.map(StressCheckinDraft.init(row:)) ?? StressCheckinDraft(localDate: day)
        )
    }

    /// Upserts this moment's half of today's row — only if it changed.
    ///
    /// The date is taken at SAVE time, as `CheckinService.save` takes the check-in's,
    /// so that an evening finished just after midnight lands on the same date in both
    /// tables and the server's join still holds (brief §4.3).
    func save(patientId: String, context: StressCheckinContext, draft: StressCheckinDraft) async throws -> StressSaveOutcome {
        let at = now()
        let day = ISO8601.dayString(at, calendar: calendar)
        guard context.window.contains(day) else { return .windowClosed }

        let part = context.part
        let sameDay = day == context.original.localDate
        if sameDay {
            guard draft.differs(from: context.original, in: part) else { return .nothingToSave }
        } else {
            guard !draft.isEmpty(part) else { return .nothingToSave }
        }

        let write = StressDiaryWrite(
            patientId: patientId,
            assessmentId: context.window.assessmentId,
            localDate: day,
            timezone: calendar.timeZone.identifier,
            part: part,
            morning: draft.morning,
            evening: draft.evening,
            at: at,
            isFirstWrite: !(sameDay && context.original.existedOnServer)
        )
        try await backend.upsertStressDiaryDay(write)
        return .saved
    }
}
