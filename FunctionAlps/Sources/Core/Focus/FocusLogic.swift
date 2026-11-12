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

    /// The tick: on to the next step, or the finish screen after the last.
    mutating func tick() { if index < total { index += 1 } }
    mutating func back() { if index > 0 { index -= 1 } }
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

    /// The pills shown: what the member did today first, then the generic ones. A key already saved (a habit since undone) stays offered.
    static func options(plan: HabitPlan?, offers: [FocusOffer], saved: [String]) -> [PillOption] {
        var options = completedToday(plan: plan, offers: offers) + genericOptions()
        let known = Set(options.map(\.key))
        for key in saved where !known.contains(key) && key.hasPrefix("habit:") {
            options.insert(PillOption(key: key, label: String(localized: "followup.pill.habit", defaultValue: "A habit")), at: 0)
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
