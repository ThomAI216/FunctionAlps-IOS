import Foundation

/// The Sleep pillar's 14-night observation, app side.
///
/// Spec: FunctionAlps-CLINICAL `docs/wiki/four-pillars/01_SLEEP_PILLAR_SPEC.md` §3.
/// The derivation, coverage and safety rules live in `clinical-dashboard/lib/sleep/`;
/// nothing here computes a metric, and nothing here decides a flag.
///
/// Two product rules this file exists to keep honest:
///  1. **No score.** Not a sleep score, not a grade, not a streak. `FAColor.scale`
///     — the 5-level functional ramp the check-in uses — is deliberately never
///     applied to a sleep domain.
///  2. **Three layers stay three.** What the member reports, what the watch
///     estimated, and what FunctionAlps derives are separate, and a device value
///     never fills a member field. A live Thryve latency of `0` is why.

/// Why a member started a fortnight. Same machinery either way — the safety screen
/// in particular is identical — only the framing of the question differs.
enum SleepTrackIntent: String, Sendable, CaseIterable, Identifiable {
    /// The member named a complaint.
    case focus
    /// Nothing is obviously wrong; the member wants to see the pattern.
    case baseline
    var id: String { rawValue }
}

/// How long the observation runs. `.short` exists as an escape hatch offered at
/// day 3–5 to a member already missing mornings — never as an up-front choice,
/// because it can never reach high coverage and nothing on the picker would say so.
enum SleepTrackProtocolLength: Int, Sendable {
    case short = 7
    case standard = 14
    case extended = 21
}

/// One morning's answers. `SLP_ASSESS_M01`–`M11`, in field order.
///
/// Every optional is an honest unknown, not a zero. "Not sure" is an answer the
/// diary offers on M03 and M05, and it costs the member that one metric for that
/// one night — never the night, and never the fortnight's coverage.
struct MorningLog: Sendable, Equatable, Identifiable {
    /// The local date the member woke on, in the zone they were actually in.
    let day: String
    /// M01 — "HH:mm", as the member typed it.
    var inBed: String?
    /// M02 — lights out, which is not the same as M01.
    var trySleep: String?
    /// M03 — minutes. Member-entered only. Never prefilled from the watch.
    var latencyMin: Int?
    /// M04 — remembered awakenings.
    var awakenings: Int?
    /// M05 — minutes awake after first falling asleep.
    var wasoMin: Int?
    /// M06 — the last waking, after which sleep did not resume.
    var finalWake: String?
    /// M07
    var outOfBed: String?
    /// M08 — 0…10
    var restoration: Int?
    /// M09 — 0…10
    var sleepiness: Int?
    /// M10 — 0…10, a FunctionAlps signal and not a validated scale.
    var overall: Int?
    /// M11
    var unusual: Set<String> = []

    var completedAt: Date?
    /// Minutes between waking and logging. A late log is kept and marked, not dropped.
    var recallDelayMin: Int?

    var id: String { day }

    /// Placeable on a timeline — the only thing a night needs to count toward the
    /// period. Each metric then reports its own denominator.
    var hasTiming: Bool {
        inBed != nil && trySleep != nil && finalWake != nil && outOfBed != nil
    }

    var isLogged: Bool { completedAt != nil }

    /// Still inside the 48-hour backfill window. A recalled night with its delay
    /// recorded beats a NULL — and nothing else in the programme produces the
    /// adherence the coverage thresholds assume.
    static func isBackfillable(day: String, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let date = ISO8601.date(fromDay: day, calendar: calendar) else { return false }
        guard let deadline = calendar.date(byAdding: .hour, value: 48, to: date) else { return false }
        return now < deadline
    }
}

/// The fortnight itself.
struct SleepTrack: Sendable, Equatable {
    let intent: SleepTrackIntent
    let length: SleepTrackProtocolLength
    let startedOn: String
    var nights: [MorningLog]

    var totalNights: Int { length.rawValue }
    var loggedCount: Int { nights.filter(\.isLogged).count }
    var placeableCount: Int { nights.filter { $0.isLogged && $0.hasTiming }.count }
    /// 1-based, for "Night 6 of 14".
    var currentNight: Int { min(nights.count, totalNights) }

    /// The night the member still owes us this morning, if any.
    var openThisMorning: MorningLog? { nights.last.flatMap { $0.isLogged ? nil : $0 } }

    /// An earlier morning still inside its window.
    var backfillable: MorningLog? {
        nights.dropLast().first { !$0.isLogged && MorningLog.isBackfillable(day: $0.day) }
    }

    /// Counts only — never a conclusion, and never before the fortnight closes.
    var freeDaysCovered: Int { freeDays.filter { day in nights.first { $0.day == day }?.isLogged == true }.count }
    var freeDays: [String] = []
}

/// Minimal day-key helpers, matching `ISO8601.day` used elsewhere in the app.
extension ISO8601 {
    static func date(fromDay day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return calendar.date(from: c)
    }
}
