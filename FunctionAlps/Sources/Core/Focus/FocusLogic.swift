import Foundation

// Today's focus on the phone — what the card shows, how the kickoff routine is walked, and the evening follow-up.
// Everything here is pure: the decisions (which cell, which habits, the wording) are the server's (`member-daily-focus`).

// MARK: - The Home card

/// What Home draws for today's focus.
enum FocusCardState: Sendable, Equatable {
    /// No morning check-in yet: the card is the way in.
    case needsCheckin
    /// The matrix cell, with the habit chips it offers (rank order, three at most).
    case cell(FocusCell, chips: [FocusOffer])
    /// A day computed before the matrix existed (a server not yet deployed): its offers as they were.
    case offersOnly(lead: FocusOffer, also: [FocusOffer])
    /// Nothing to say.
    case nothing
}

enum FocusCardLogic {
    static let maxChips = 3

    static func state(_ today: TodayFocus) -> FocusCardState {
        if today.needsCheckin { return .needsCheckin }
        if let cell = today.cell { return .cell(cell, chips: chips(today.offers)) }
        if let lead = today.focus { return .offersOnly(lead: lead, also: today.alsoToday) }
        return .nothing
    }

    /// The offers that open an action card, in the server's rank order.
    static func chips(_ offers: [FocusOffer]) -> [FocusOffer] {
        let ranked = offers.filter { $0.bankCardId != nil }.sorted { ($0.rank ?? 99) < ($1.rank ?? 99) }
        return Array(ranked.prefix(maxChips))
    }

    /// The kickoff button is shown only when the cell offers a routine with something to walk.
    static func kickoff(_ cell: FocusCell) -> FocusKickoff? {
        guard let kickoff = cell.kickoff, kickoff.steps.count >= 2 else { return nil }
        return kickoff
    }
}

// MARK: - The kickoff morning routine

/// Where the member is in the routine: one screen per step, a tick to go on, then the finish screen.
struct KickoffProgress: Sendable, Equatable {
    let total: Int
    /// 0 ..< total is a step; `total` is the finish screen.
    private(set) var index = 0

    init(total: Int) { self.total = max(0, total) }

    var isFinished: Bool { index >= total }
    /// "Step 2 of 6" — 1-based, never past the last step.
    var stepNumber: Int { min(index + 1, total) }
    var canGoBack: Bool { index > 0 }
    /// Steps ticked so far (the finish screen = every step).
    var stepsDone: Int { index }

    /// The tick: on to the next step, or the finish screen after the last.
    mutating func tick() { if index < total { index += 1 } }
    mutating func back() { if index > 0 { index -= 1 } }
}

// MARK: - The kickoff row on Home

/// The one green row Home's routine card carries on a hard morning (owner, 2026-11-13): "Kickoff morning routine", at the top of the
/// list once the morning check-in is done. Tapping it walks the routine; finishing the walk ticks it for the day. It is due within an
/// hour of waking (`KickoffDeadline`); past that it says "Missed", still open, and finished after that it says "Done late".
struct KickoffRow: Sendable, Equatable {
    /// The focus headline of the day.
    let subtitle: String
    /// When the routine is due; nil only when the day could not be read.
    let dueAt: Date?
    let completedAt: Date?

    var done: Bool { completedAt != nil }
    func status(now: Date) -> KickoffStatus { KickoffDeadline.status(dueAt: dueAt, completedAt: completedAt, now: now) }
}

enum KickoffRowLogic {
    /// Only on a hard morning whose cell offers a routine with something to walk, once the morning check-in is saved, in the morning
    /// and the day's routines (never the evening's, never on a day with no cell). The deadline is the run's own when the table already
    /// holds the day (it stays fixed once offered), else worked out from the wake time.
    static func row(focus: TodayFocus?, slot: HabitSlot, morningCheckinDone: Bool, run: KickoffRun?, wakeTime: String?,
                    calendar: Calendar = .current) -> KickoffRow? {
        guard morningCheckinDone, slot != .evening, let focus, !focus.needsCheckin,
              let cell = focus.cell, cell.hardMorning, FocusCardLogic.kickoff(cell) != nil else { return nil }
        let own = run.flatMap { $0.day == focus.day ? $0 : nil }
        let due = own?.dueAt ?? KickoffDeadline.dueAt(day: focus.day, wakeTime: wakeTime, calendar: calendar)
        return KickoffRow(subtitle: cell.headline, dueAt: due, completedAt: own?.completedAt)
    }

    /// Where the run is kept on this phone while the table cannot be reached (and the only copy for a database without the table).
    /// One JSON value, so a new day is simply another day's value.
    static let localRunKey = "fa.focus.kickoffRun"
}

/// Open until the deadline; missed after it; done, or done late.
enum KickoffStatus: Sendable, Equatable { case open, missed, done, doneLate }

/// The kickoff morning routine is due within an hour of waking (owner, 2026-11-13). The wake time is last night's, as the morning
/// check-in recorded it (the sleep answers, or the wearable's night); without one the deadline is 10:00 local.
enum KickoffDeadline {
    static let graceMinutes = 60
    static let fallbackHour = 10

    /// The deadline on the member's local `day` (`YYYY-MM-DD`): wake time plus an hour, else 10:00. Nil when the day cannot be read.
    static func dueAt(day: String, wakeTime: String?, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var parsed = DateComponents()
        parsed.year = parts[0]; parsed.month = parts[1]; parsed.day = parts[2]
        guard let start = calendar.date(from: parsed) else { return nil }
        let startOfDay = calendar.startOfDay(for: start)
        if let wake = SleepSpecials.clock(wakeTime).flatMap(SleepSpecials.minutes) {
            return calendar.date(byAdding: .minute, value: wake + graceMinutes, to: startOfDay)
        }
        return calendar.date(byAdding: .hour, value: fallbackHour, to: startOfDay)
    }

    /// Derived, never stored: done on time = completed by the deadline (or no deadline); done late = completed after it;
    /// missed = not completed and past it; open otherwise.
    static func status(dueAt: Date?, completedAt: Date?, now: Date) -> KickoffStatus {
        if let completedAt {
            guard let dueAt else { return .done }
            return completedAt <= dueAt ? .done : .doneLate
        }
        guard let dueAt else { return .open }
        return now > dueAt ? .missed : .open
    }

    /// "07:45", in the member's own clock.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}

/// One `patient_routine_runs` row (`routine = 'kickoff_morning'`): the routine offered on a day, when it was due, how far the member
/// walked, and when they finished. The clinic reads it; the status is derived from these columns (`KickoffDeadline.status`).
struct KickoffRun: Sendable, Equatable, Codable {
    static let routine = "kickoff_morning"
    static let maxSteps = 20

    let day: String
    var focusCell: String?
    var offeredAt: Date
    var dueAt: Date?
    var completedAt: Date?
    var stepsDone: Int

    func status(now: Date) -> KickoffStatus { KickoffDeadline.status(dueAt: dueAt, completedAt: completedAt, now: now) }
}

enum KickoffRunLogic {
    private static func base(_ patientId: String, _ day: String) -> ColumnPatch {
        ["patient_id": .string(patientId), "day": .string(day), "routine": .string(KickoffRun.routine)]
    }

    /// The first time the green row is shown: the offer (when, until when, on which cell). A merge-duplicates upsert updates every key
    /// in the body, so this is only sent when the day has no row yet — and carries what a local copy already knows.
    static func offerColumns(_ run: KickoffRun, patientId: String) -> ColumnPatch {
        var row = base(patientId, run.day)
        row["focus_cell"] = .string(run.focusCell)
        row["offered_at"] = .string(ISO8601.string(run.offeredAt))
        row["due_at"] = run.dueAt.map { ColumnValue.string(ISO8601.string($0)) } ?? ColumnValue.null
        row["steps_done"] = .int(min(max(run.stepsDone, 0), KickoffRun.maxSteps))
        if let done = run.completedAt { row["completed_at"] = ColumnValue.string(ISO8601.string(done)) }
        return row
    }

    /// A step ticked: only the count moves.
    static func progressColumns(_ run: KickoffRun, patientId: String) -> ColumnPatch {
        var row = base(patientId, run.day)
        row["steps_done"] = .int(min(max(run.stepsDone, 0), KickoffRun.maxSteps))
        return row
    }

    /// The walk finished: the moment, and the count.
    static func completionColumns(_ run: KickoffRun, patientId: String) -> ColumnPatch {
        var row = progressColumns(run, patientId: patientId)
        row["completed_at"] = run.completedAt.map { ColumnValue.string(ISO8601.string($0)) } ?? ColumnValue.null
        return row
    }
}

/// What Home's routine card does for a member on the Foundation Track (owner, 2026-11-13): the same card as everyone else, so the
/// kickoff row reaches them too. Their track actions stay in the track's own card under it, and the card never shows the blurred
/// "no actions yet" place for them (that would say nothing is planned while the track card lists the day's actions).
enum PlanTodayLogic {
    enum Mode: Equatable { case card, placeholder, hidden }

    static func mode(onTrack: Bool, hasPlanHabits: Bool, hasKickoff: Bool, showsCheckin: Bool) -> Mode {
        if hasPlanHabits || hasKickoff || showsCheckin { return .card }
        return onTrack ? .hidden : .placeholder
    }

    static func showsNoActionsArea(onTrack: Bool, withCheckin: Bool, hasPlanHabits: Bool) -> Bool {
        withCheckin && !hasPlanHabits && !onTrack
    }
}

// MARK: - The evening follow-up

/// After a hard morning, the daily check-in asks how the rest of the day went and what made the difference. Stored on today's
/// `patient_day_feelings` row (`evening_followup` -1 · 0 · 1, `evening_pills` a list of keys).
struct EveningFollowup: Sendable, Equatable {
    enum Choice: Int, Sendable, CaseIterable {
        case harder = -1, same = 0, better = 1
    }

    var choice: Choice?
    var pills: [String] = []

    var isEmpty: Bool { choice == nil && pills.isEmpty }
}

enum EveningFollowupLogic {
    /// Asked in the DAILY check-in (the evening slot), for today (not a caught-up day), when the focus cell says the morning was hard.
    static func isAsked(cell: FocusCell?, slot: MomentSlot, catchingUp: Bool) -> Bool {
        slot == .evening && !catchingUp && cell?.hardMorning == true
    }

    /// Generic answers beside the habits the member completed today.
    static let genericKeys = ["rest", "food", "people", "work", "movement", "sleep_debt"]

    static func genericOptions() -> [PillOption] {
        [PillOption(key: "rest", label: String(localized: "followup.pill.rest", defaultValue: "Rest")),
         PillOption(key: "food", label: String(localized: "followup.pill.food", defaultValue: "Food")),
         PillOption(key: "people", label: String(localized: "followup.pill.people", defaultValue: "People")),
         PillOption(key: "work", label: String(localized: "followup.pill.work", defaultValue: "Work")),
         PillOption(key: "movement", label: String(localized: "followup.pill.movement", defaultValue: "Movement")),
         PillOption(key: "sleep_debt", label: String(localized: "followup.pill.sleepDebt", defaultValue: "Sleep debt"))]
    }

    static func habitKey(_ id: String) -> String { "habit:\(id)" }

    /// The pill for the kickoff morning routine (offered that morning).
    static let kickoffKey = "kickoff"
    static func kickoffLabel() -> String { String(localized: "kickoff.row.title", defaultValue: "Kickoff morning routine") }

    /// The habits done today: the plan's habits with a completion today, and the focus offers ticked as done — each once, by title.
    static func completedToday(plan: HabitPlan?, offers: [FocusOffer]) -> [PillOption] {
        var out: [PillOption] = []
        var seen: Set<String> = []
        func add(_ key: String, _ title: String) {
            let folded = title.lowercased()
            guard !seen.contains(folded) else { return }
            seen.insert(folded)
            out.append(PillOption(key: key, label: title))
        }
        if let plan {
            let doneIds = Set(plan.completions.filter { $0.day == plan.day }.map(\.habitId))
            for habit in plan.habits where doneIds.contains(habit.id) {
                add(habitKey(habit.habitBankId ?? habit.id), habit.title)
            }
        }
        for offer in offers where offer.completed {
            add(habitKey(offer.bankCardId ?? offer.id), offer.title)
        }
        return out
    }

    /// Everything the morning proposed, in the order it proposed it: the kickoff routine when the cell offered it, then one pill per
    /// habit the day's focus offered (rank order, by title) — whether or not the member did it.
    static func proposed(focus: TodayFocus?) -> [PillOption] {
        guard let focus else { return [] }
        var out: [PillOption] = []
        if let cell = focus.cell, FocusCardLogic.kickoff(cell) != nil { out.append(PillOption(key: kickoffKey, label: kickoffLabel())) }
        let ranked = focus.offers.enumerated().sorted { ($0.element.rank ?? 99, $0.offset) < ($1.element.rank ?? 99, $1.offset) }
        for (_, offer) in ranked { out.append(PillOption(key: habitKey(offer.bankCardId ?? offer.id), label: offer.title)) }
        return out
    }

    /// The pills shown, deduped by key and by title: what the morning proposed, then the habits done today that are not already
    /// listed, then the generic answers. A key already saved (a habit since undone) stays offered.
    static func options(plan: HabitPlan?, focus: TodayFocus?, saved: [String]) -> [PillOption] {
        var options: [PillOption] = []
        var keys: Set<String> = []
        var titles: Set<String> = []
        func append(_ list: [PillOption]) {
            for option in list where !keys.contains(option.key) && !titles.contains(option.label.lowercased()) {
                keys.insert(option.key)
                titles.insert(option.label.lowercased())
                options.append(option)
            }
        }
        append(proposed(focus: focus))
        append(completedToday(plan: plan, offers: focus?.offers ?? []))
        append(genericOptions())
        for key in saved where !keys.contains(key) {
            if key == kickoffKey {
                options.insert(PillOption(key: key, label: kickoffLabel()), at: 0)
            } else if key.hasPrefix("habit:") {
                options.insert(PillOption(key: key, label: String(localized: "followup.pill.habit", defaultValue: "A habit")), at: 0)
            }
        }
        return options
    }

    static func toggled(_ pills: [String], _ key: String) -> [String] {
        pills.contains(key) ? pills.filter { $0 != key } : pills + [key]
    }

    /// The columns written to `patient_day_feelings` — ONLY these two (plus the row's key), so the morning's own answers on the
    /// same row are never touched: PostgREST's merge-duplicates writes every key it is sent and leaves the rest alone.
    static func columns(_ followup: EveningFollowup, patientId: String, day: String) -> ColumnPatch {
        [
            "patient_id": .string(patientId),
            "day": .string(day),
            "evening_followup": .int(followup.choice?.rawValue),
            "evening_pills": .json(.array(followup.pills.map { JSONValue.string($0) })),
        ]
    }
}
