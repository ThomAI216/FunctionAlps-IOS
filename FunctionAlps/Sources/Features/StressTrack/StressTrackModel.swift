import Foundation

/// The Stress, Recovery & Connection pillar's observation period, app side.
///
/// Spec:  FunctionAlps-CLINICAL `docs/wiki/four-pillars/10_STRESS_PILLAR_SPEC.md` §3.
/// Scope: `09_STRESS_MENTAL_HEALTH_SCOPE.md` (binding — it wins over the spec).
/// Brief: `docs/STRESS_TRACK_IMPLEMENTATION.md`.
///
/// THIS FEATURE DOES NOT BUILD A SECOND DAILY FORM. While a Stress track runs, the
/// check-in the member already does gains a few items at the end — three in the
/// morning, six in the evening — and nothing else changes. Mood and calm are NOT
/// asked again and are NOT copied anywhere: they stay in the check-in, and the
/// server reads them from there.
///
/// The derivation, coverage, flags and the profile live in
/// `clinical-dashboard/lib/stress/`. Nothing here computes a metric, nothing here
/// decides a flag, and nothing here is ever shown back to the member as a number.
///
/// Four rules these types exist to keep honest:
///  1. **No score.** Not a stress score, not a resilience score, not a streak. None
///     of these types has a score field, and `FAColor.scale` never touches them.
///  2. **Calm is calm.** The check-in's `stressScore` stores CALMNESS (0–100, higher
///     = calmer). This feature never reads it, never writes it, never inverts it.
///  3. **NULL, never 0.** Every item can be skipped, and a skipped item costs that one
///     metric on that one day — never the day. Tapping a chosen answer again clears it.
///  4. **A follow-up exists only behind its "yes".** Work detachment only on an
///     obligation day the member did not mark "I didn't work today"; what-and-how-much
///     only when they did something restorative.

// MARK: - Which half of the day

/// The two check-in moments that carry additions. Midday carries none.
enum StressDiaryPart: String, Sendable, Equatable, CaseIterable {
    /// S1–S3: recovered · unwell · alcohol last evening.
    case morning
    /// S4–S9: peak · back to normal · still carrying · day type (then work) ·
    /// restorative · connection.
    case evening

    init?(slot: MomentSlot) {
        switch slot {
        case .morning: self = .morning
        case .evening: self = .evening
        case .midday: return nil
        }
    }
}

// MARK: - Answer sets

/// S5 — "After the hardest moment, how long until you felt close to normal?"
///
/// **ORDINAL.** The six measured bands are ranked 0 (under ten minutes) to 5 (not
/// back to normal that day), in exactly the order of `RECOVERY_LATENCY_BANDS` in
/// `lib/stress/types.ts`. The server summarises them as a median band — never
/// minutes, never an average — so this app never converts a band to a number.
///
/// `noStressor` is NOT a fast recovery. It is the absence of the thing measured, and
/// the engine excludes it. It is rendered apart from the six bands for that reason.
///
/// The raw values are exactly the seven the `stress_diary_day` CHECK constraint
/// accepts (migration 205). They are a contract: the labels may change, these may not.
enum RecoveryLatencyBand: String, Codable, Sendable, CaseIterable, Identifiable {
    case under10m = "under_10m"
    case from10to30m = "10_30m"
    case from30to60m = "30_60m"
    case from1to3h = "1_3h"
    case over3h = "over_3h"
    case never
    case noStressor = "no_stressor"

    var id: String { rawValue }

    /// The six bands that measure something, in the engine's ordinal order.
    static let measured: [RecoveryLatencyBand] = [.under10m, .from10to30m, .from30to60m, .from1to3h, .over3h, .never]

    /// Same wording as the MEMBERS web check-in, so one instrument reads the same on
    /// both surfaces.
    var label: String {
        switch self {
        case .under10m: String(localized: "stressTrack.latency.under10m", defaultValue: "Under 10 min")
        case .from10to30m: String(localized: "stressTrack.latency.10to30m", defaultValue: "10–30 min")
        case .from30to60m: String(localized: "stressTrack.latency.30to60m", defaultValue: "30–60 min")
        case .from1to3h: String(localized: "stressTrack.latency.1to3h", defaultValue: "1–3 hours")
        case .over3h: String(localized: "stressTrack.latency.over3h", defaultValue: "Over 3 hours")
        case .never: String(localized: "stressTrack.latency.never", defaultValue: "Not yet today")
        case .noStressor: String(localized: "stressTrack.latency.noStressor", defaultValue: "Nothing really stressful today")
        }
    }
}

/// S8 follow-up — "What was it?" (`pm_restorative_types`, text[]).
///
/// The keys follow the questionnaire's `recovery_activities` wherever one exists, so
/// what the member said helps and what they actually did can be read side by side.
/// They are the MEMBERS web check-in's keys (13), verbatim and in its order. The server
/// shows a key with `_` as a space, so every key is a plain word.
///
/// `breathing` and `meditation` are TWO keys, as in the questionnaire: merged, a member
/// who meditated would later read "Most often: breathing" in the profile.
///
/// The column has no CHECK constraint, so **unknown keys are preserved**: the draft
/// holds the raw strings, and a key another surface wrote that this list does not
/// know survives an edit made here.
enum RestorativeType: String, Sendable, CaseIterable, Identifiable {
    case walking, outdoors, exercise, breathing, meditation, alone, family, friends, creative, heat, sleep, screens, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .walking: String(localized: "stressTrack.restore.walking", defaultValue: "A walk")
        case .outdoors: String(localized: "stressTrack.restore.outdoors", defaultValue: "Time outdoors")
        case .exercise: String(localized: "stressTrack.restore.exercise", defaultValue: "Exercise or sport")
        case .breathing: String(localized: "stressTrack.restore.breathing", defaultValue: "Slow breathing or relaxation")
        case .meditation: String(localized: "stressTrack.restore.meditation", defaultValue: "Meditation")
        case .alone: String(localized: "stressTrack.restore.alone", defaultValue: "Quiet time alone")
        case .family: String(localized: "stressTrack.restore.family", defaultValue: "Time with partner or family")
        case .friends: String(localized: "stressTrack.restore.friends", defaultValue: "Time with friends")
        case .creative: String(localized: "stressTrack.restore.creative", defaultValue: "Reading, music, something creative")
        case .heat: String(localized: "stressTrack.restore.heat", defaultValue: "A bath or sauna")
        case .sleep: String(localized: "stressTrack.restore.sleep", defaultValue: "A nap or an early night")
        case .screens: String(localized: "stressTrack.restore.screens", defaultValue: "A film, series or game")
        case .other: String(localized: "stressTrack.restore.other", defaultValue: "Something else")
        }
    }
}

/// Which surface wrote a row (`logged_via` / `updated_via`).
enum StressSurface: String, Codable, Sendable, Equatable {
    case ios, web
}

// MARK: - The day's answers, as the screen edits them

/// The additions for one local date, as the check-in screen holds them.
///
/// Split into the two halves of the day because they are WRITTEN separately: the
/// morning save carries only the morning columns and the evening save only the
/// evening ones, so neither half can ever null the other (see `StressDiaryWrite`).
struct StressCheckinDraft: Sendable, Equatable {
    struct Morning: Sendable, Equatable {
        /// S1 · `am_recovered` · 0…10
        var recovered: Int?
        /// S2 · `am_unwell` — a confounder, never a flag. An unwell day is kept and
        /// shown, and the server leaves it out of every comparison.
        var unwell: Bool?
        /// S3 · `alcohol_last_evening` — a confounder. Yes or no, never an amount.
        var alcoholLastEvening: Bool?

        var isEmpty: Bool { recovered == nil && unwell == nil && alcoholLastEvening == nil }
    }

    struct Evening: Sendable, Equatable {
        /// S4 · `pm_peak` · 0…10
        var peak: Int?
        /// S5 · `pm_recovery_latency`
        var recoveryLatency: RecoveryLatencyBand?
        /// S6 · `pm_carryover` · 0…10
        var carryover: Int?
        /// S7 · `day_type` — "What kind of day was today?" (decision 2026-09-25).
        ///
        /// The obligation/free axis every pillar shares, so it is the Nutrition track's
        /// `NutritionDayType`, reused and **not redeclared** (that type's own rule, and
        /// Nutrition brief §3). Its raw values, `obligation` and `free`, are exactly the
        /// two the `stress_diary_day.day_type` CHECK accepts (migration 205) and
        /// `DayType` in `lib/pillars/types.ts`. The engine needs it: `high` coverage
        /// requires ≥2 of each, and `free_vs_obligation_calm` reads it on every day.
        var dayType: NutritionDayType?
        /// S7, obligation day only: "I didn't work today", for an obligation day that
        /// was not work (caring, errands, admin). **Screen state only, never stored.**
        /// It writes `pm_work_detachment` NULL, the same NULL a skip writes.
        var didNotWork = false
        /// S7 follow-up · `pm_work_detachment` · 0…10. Asked only on an obligation day.
        var workDetachment: Int?
        /// S8 · `pm_restorative`
        var restorative: Bool?
        /// S8 follow-up · `pm_restorative_types` — raw keys, unknown ones preserved.
        var restorativeTypes: [String] = []
        /// S8 follow-up · `pm_restorative_effect` · 0…10
        var restorativeEffect: Int?
        /// S9 · `pm_meaningful_connection`
        var meaningfulConnection: Bool?

        /// Anything but "obligation" (a free day, or the chip cleared) hides and clears
        /// the switch-off question, as the web does. A day off is not "switched off well".
        mutating func setDayType(_ value: NutritionDayType?) {
            dayType = value
            if value != .obligation {
                didNotWork = false
                workDetachment = nil
            }
        }

        /// "I didn't work today" clears the rating: the two answer different questions.
        mutating func setDidNotWork(_ value: Bool) {
            didNotWork = value
            if value { workDetachment = nil }
        }

        /// A rating clears "I didn't work today", for the same reason.
        mutating func setWorkDetachment(_ value: Int?) {
            workDetachment = value
            if value != nil { didNotWork = false }
        }

        /// Answering anything but "yes" to S8 clears both follow-ups. The table
        /// refuses an effect without an action (`stress_diary_day_effect_needs_action`).
        mutating func setRestorative(_ value: Bool?) {
            restorative = value
            if value != true {
                restorativeTypes = []
                restorativeEffect = nil
            }
        }

        func contains(_ type: RestorativeType) -> Bool { restorativeTypes.contains(type.rawValue) }

        mutating func toggle(_ type: RestorativeType) {
            if let i = restorativeTypes.firstIndex(of: type.rawValue) {
                restorativeTypes.remove(at: i)
            } else {
                restorativeTypes.append(type.rawValue)
            }
        }

        // What actually reaches the table. A follow-up is stored only behind its "yes",
        // whatever the screen still holds.
        /// `day_type` as the column spells it. `NutritionDayType` is not `Encodable`,
        /// so the wire sends its raw value.
        var storedDayType: String? { dayType?.rawValue }
        var storedWorkDetachment: Int? { dayType == .obligation && !didNotWork ? workDetachment : nil }
        var storedRestorativeTypes: [String] { restorative == true ? restorativeTypes : [] }
        var storedRestorativeEffect: Int? { restorative == true ? restorativeEffect : nil }

        /// Compares what would be STORED, not the screen state. Tapping "I didn't work
        /// today" on a day with no rating changes no column.
        func storesSameAs(_ other: Evening) -> Bool {
            peak == other.peak
                && recoveryLatency == other.recoveryLatency
                && carryover == other.carryover
                && storedDayType == other.storedDayType
                && storedWorkDetachment == other.storedWorkDetachment
                && restorative == other.restorative
                && storedRestorativeTypes == other.storedRestorativeTypes
                && storedRestorativeEffect == other.storedRestorativeEffect
                && meaningfulConnection == other.meaningfulConnection
        }

        var isEmpty: Bool { storesSameAs(Evening()) }
    }

    /// The member's OWN local date (`YYYY-MM-DD` in the zone the phone is in), never
    /// a UTC date — computed exactly as `CheckinService.today` computes the check-in's
    /// `checkin_date`, because the server joins the two on it.
    let localDate: String
    var morning = Morning()
    var evening = Evening()

    // Provenance of the row as it was loaded — for "you last saved these on the web",
    // and so a first write can be told from an edit.
    var existedOnServer = false
    var lastUpdatedVia: StressSurface?
    var lastUpdatedAt: Date?

    init(localDate: String) {
        self.localDate = localDate
    }

    /// Prefill from the stored row, so a re-opened moment EDITS it and a day answered
    /// on the web is shown here rather than asked again.
    init(row: StressDiaryDay) {
        localDate = row.localDate
        morning = Morning(recovered: row.amRecovered, unwell: row.amUnwell, alcoholLastEvening: row.alcoholLastEvening)
        evening = Evening(
            peak: row.pmPeak,
            recoveryLatency: row.pmRecoveryLatency,
            carryover: row.pmCarryover,
            // The CHECK allows only 'obligation' and 'free', so every stored value maps.
            dayType: row.dayType.flatMap(NutritionDayType.init(rawValue:)),
            // A NULL detachment on an obligation day cannot be told apart from "didn't
            // work" or a skip (both are NULL by design), so it stays unanswered.
            didNotWork: false,
            workDetachment: row.pmWorkDetachment,
            restorative: row.pmRestorative,
            restorativeTypes: row.pmRestorativeTypes,
            restorativeEffect: row.pmRestorativeEffect,
            meaningfulConnection: row.pmMeaningfulConnection
        )
        existedOnServer = true
        lastUpdatedVia = row.updatedVia
        lastUpdatedAt = row.updatedAt.flatMap(ISO8601.parse)
    }

    func isEmpty(_ part: StressDiaryPart) -> Bool {
        switch part {
        case .morning: morning.isEmpty
        case .evening: evening.isEmpty
        }
    }

    /// Whether `part` would store anything different from `baseline`.
    func differs(from baseline: StressCheckinDraft, in part: StressDiaryPart) -> Bool {
        switch part {
        case .morning: morning != baseline.morning
        case .evening: !evening.storesSameAs(baseline.evening)
        }
    }
}

// MARK: - The running window

/// The active Stress assessment, as the check-in needs it: which window, and where
/// today falls in it. Counts only — never a conclusion, never before the window closes.
struct StressTrackWindow: Sendable, Equatable {
    let assessmentId: String
    /// 7, 14 or 21.
    let protocolDays: Int
    /// `YYYY-MM-DD`
    let startedOn: String
    /// `YYYY-MM-DD`, inclusive — exactly the engine's `stressAssessmentWindow` in
    /// `lib/stress/db.ts`: `actual_end_on`, else `planned_end_on`, else
    /// `started_on + protocol_days − 1`. The server reads only the rows inside this
    /// window, so a row written outside it would be saved and then never used.
    let lastDay: String

    /// ISO dates order lexicographically, so this is a plain string comparison.
    func contains(_ day: String) -> Bool { startedOn <= day && day <= lastDay }

    /// How many days the window holds, for "Day 6 of 14" and "after day 14". Taken
    /// from the window, not from `protocolDays`, so that a planned end that differs
    /// from the protocol can never read "Day 16 of 14".
    var dayCount: Int { (StressDays.between(startedOn, lastDay) ?? (protocolDays - 1)) + 1 }

    /// 1-based, for "Day 6 of 14". Nil outside the window.
    func dayNumber(on day: String) -> Int? {
        guard contains(day), let n = StressDays.between(startedOn, day) else { return nil }
        return n + 1
    }
}

extension StressTrackWindow {
    /// Nil unless the row really is an ACTIVE STRESS assessment. The query already
    /// filters on both, and this checks again on purpose: the member RLS policy on
    /// `stress_diary_day` checks that the assessment is active, not that it is a Stress
    /// one, so the only thing stopping a write against a running Sleep window is the
    /// id this app chooses to send.
    init?(row: StressAssessmentRow) {
        guard row.isActiveStress else { return nil }
        let last = row.actualEndOn ?? row.plannedEndOn ?? StressDays.adding(row.protocolDays - 1, to: row.startedOn)
        guard let last else { return nil }
        self.init(assessmentId: row.id, protocolDays: row.protocolDays, startedOn: row.startedOn, lastDay: last)
    }
}

/// Calendar arithmetic on `YYYY-MM-DD` strings, in a fixed UTC calendar so that a
/// day count never moves with the phone's zone or a DST change.
enum StressDays {
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        if let zone = TimeZone(secondsFromGMT: 0) { c.timeZone = zone }
        return c
    }()

    static func adding(_ days: Int, to day: String) -> String? {
        guard let date = ISO8601.parse(day), let moved = utc.date(byAdding: .day, value: days, to: date) else { return nil }
        return ISO8601.dayString(moved, calendar: utc)
    }

    static func between(_ from: String, _ to: String) -> Int? {
        guard let a = ISO8601.parse(from), let b = ISO8601.parse(to) else { return nil }
        return utc.dateComponents([.day], from: a, to: b).day
    }
}

// MARK: - Who is asked about switching off from work

/// Whether S7's switch-off question ("How well have you switched off from work?") can
/// show on an obligation day.
///
/// **It gates the follow-up only, never the day-type chip.** Since 2026-09-25 S7 opens
/// with the obligation/free chip, and every member sees it: coverage and the
/// free-vs-obligation pattern need a day type from everyone, whether or not they
/// named work. Before that, this gate hid the whole of S7.
///
/// Mirror of `WORK_TRIGGER` in `clinical-dashboard/lib/stress/questionnaire.ts`: the
/// questionnaire's work section opens when work is named as a source of stress, or
/// "work follows me" as a goal. A member for whom it never opened is told, on their
/// results, that work was not asked about, so the evening does not ask either.
///
/// **If `WORK_TRIGGER` changes, change this.** It is a visibility rule, not a metric,
/// and it fails OPEN: a questionnaire that cannot be read, or is not yet submitted,
/// shows the question. Showing a skippable item costs one tap; hiding it from someone
/// who works loses the whole domain.
enum StressWorkGate {
    static let workSources: Set<String> = ["workload", "work_control", "work_relationships", "business"]
    static let workGoal = "work_follows_me"

    static func opensWorkSection(sources: [String], goals: [String]) -> Bool {
        sources.contains { workSources.contains($0) } || goals.contains(workGoal)
    }

    static func showsWorkDetachment(_ questionnaire: StressQuestionnaireWorkRow?) -> Bool {
        guard let questionnaire, questionnaire.isSubmitted else { return true }
        return opensWorkSection(sources: questionnaire.stressSources ?? [], goals: questionnaire.stressGoal ?? [])
    }
}
