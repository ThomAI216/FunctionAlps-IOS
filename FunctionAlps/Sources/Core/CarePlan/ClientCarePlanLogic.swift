import Foundation

/// Pure shaping of the client's care plan for the Today card, the Plan page, the objective page, "Why we're doing
/// this", "Your situation & evolution" and the Journey (CLINICAL 2026-11-12). Counting, ordering, wording of a status:
/// no clock (the day is passed in), no I/O, nothing computed from a health signal (rule 9). Every sentence the member
/// reads about themselves is the practice's, passed through untouched; the only words written here are labels for a
/// status the practice chose from a fixed list.
enum ClientCarePlanLogic {
    // MARK: Programmes, weeks and phases

    /// Programmes in the practice's order (`position`, then start date).
    static func ordered(_ programmes: [ClientProgramme]) -> [ClientProgramme] {
        programmes.enumerated().sorted { a, b in
            let pa = a.element.position ?? Int.max, pb = b.element.position ?? Int.max
            if pa != pb { return pa < pb }
            let sa = a.element.startDate ?? "", sb = b.element.startDate ?? ""
            if sa != sb { return sa < sb }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The programme the Today card and the Plan lead with: the first active one, else nil.
    static func leadProgramme(_ raw: ClientCarePlanRaw) -> ClientProgramme? {
        ordered(raw.programmes).first(where: \.isActive)
    }

    /// Whether the Journey screen is worth opening: more than one programme to show (owner, 2026-11-12).
    static func showsJourney(_ raw: ClientCarePlanRaw) -> Bool { raw.programmes.count > 1 }

    /// The programme's phases in order.
    static func phases(_ programme: ClientProgramme) -> [ClientPhase] {
        (programme.phases ?? []).enumerated().sorted { a, b in
            let oa = a.element.sortOrder ?? Int.max, ob = b.element.sortOrder ?? Int.max
            if oa != ob { return oa < ob }
            let wa = a.element.weekStart ?? Int.max, wb = b.element.weekStart ?? Int.max
            if wa != wb { return wa < wb }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Programme week on `today` (1 = the first week); nil when it has no usable start or has not started.
    static func week(of programme: ClientProgramme, today: String) -> Int? {
        guard let start = programme.startDate.map({ String($0.prefix(10)) }),
              let days = HabitEngine.daysBetween(start, today), days >= 0 else { return nil }
        return days / 7 + 1
    }

    /// The programme's length in weeks: what the practice planned, else the last phase's end.
    static func totalWeeks(of programme: ClientProgramme) -> Int? {
        if let planned = programme.plannedWeeks, planned > 0 { return planned }
        return (programme.phases ?? []).compactMap(\.weekEnd).max()
    }

    enum PhaseState: Equatable, Sendable { case done, current, upcoming }

    struct PhaseStep: Equatable, Sendable, Identifiable {
        let number: Int
        let title: String?
        let state: PhaseState
        var id: Int { number }
    }

    /// The phase bar: each phase with where the member stands in it. A nil week (no start yet) = every phase upcoming.
    static func phaseSteps(_ programme: ClientProgramme, week: Int?) -> [ClientCarePlanLogic.PhaseStep] {
        phases(programme).enumerated().map { index, phase in
            let state: PhaseState
            if let week, let start = phase.weekStart {
                if week < start { state = .upcoming }
                else if let end = phase.weekEnd, week > end { state = .done }
                else { state = .current }
            } else {
                state = .upcoming
            }
            return PhaseStep(number: index + 1, title: phase.title, state: state)
        }
    }

    /// 1-based number of the phase the week falls in, with the phase count ("Phase 2 of 3"); nil when none is current.
    static func currentPhase(_ programme: ClientProgramme, week: Int?) -> (number: Int, of: Int, title: String?)? {
        let steps = phaseSteps(programme, week: week)
        guard let current = steps.first(where: { $0.state == .current }) else { return nil }
        return (current.number, steps.count, current.title)
    }

    // MARK: Objectives

    /// The words the member reads: their own when the practice kept them, else the statement.
    static func title(_ objective: ClientObjective) -> String {
        for text in [objective.clientVerbatim, objective.statement] {
            if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        }
        return ""
    }

    /// Whether the member's own words lead (shown in quotes).
    static func usesOwnWords(_ objective: ClientObjective) -> Bool {
        !(objective.clientVerbatim?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Objectives of one programme (all of them when `programmeId` is nil), in the practice's order, achieved last.
    static func objectives(_ raw: ClientCarePlanRaw, programmeId: String? = nil) -> [ClientObjective] {
        let rows = raw.objectives.filter { programmeId == nil || $0.programmeId == programmeId || $0.programmeId == nil }
        return rows.filter { $0.status != "achieved" } + rows.filter { $0.status == "achieved" }
    }

    /// The comparators that mean "the lower the better".
    private static func lowerIsBetter(_ comparator: String?) -> Bool { comparator == "<" || comparator == "<=" }

    struct OutcomeLine: Equatable, Sendable, Identifiable {
        let id: String
        let label: String
        /// 0…1.
        let fraction: Double
        let met: Bool
        let current: Double?
        let target: Double?
        let unit: String?
        let lowerIsBetter: Bool
        let dueDate: String?
    }

    /// One outcome as a progress line. Progress runs from the baseline to the target when both are known (so it works
    /// for "up to 14" and "down to 3" alike), else current over target; a met outcome is full.
    static func line(_ outcome: ClientOutcome) -> OutcomeLine {
        let met = outcome.status == "met"
        var fraction = 0.0
        if met {
            fraction = 1
        } else if let current = outcome.currentValue, let target = outcome.targetValue {
            if let baseline = outcome.baselineValue, baseline != target {
                fraction = (current - baseline) / (target - baseline)
            } else if target > 0, !lowerIsBetter(outcome.comparator) {
                fraction = current / target
            } else if lowerIsBetter(outcome.comparator) {
                fraction = current <= target ? 1 : 0
            }
        }
        let label = outcome.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return OutcomeLine(id: outcome.id, label: label, fraction: min(max(fraction.isFinite ? fraction : 0, 0), 1), met: met,
                           current: outcome.currentValue, target: outcome.targetValue, unit: outcome.unit,
                           lowerIsBetter: lowerIsBetter(outcome.comparator), dueDate: outcome.dueDate)
    }

    static func lines(_ objective: ClientObjective) -> [OutcomeLine] {
        (objective.outcomes ?? []).map(line).filter { !$0.label.isEmpty }
    }

    /// "6", "2.5": whole numbers without a decimal point.
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// The right-hand text of an outcome line: "6 of 14 days", "now 5 · target 3", or the status when no numbers.
    static func progressText(_ line: OutcomeLine) -> String {
        let unit = line.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = unit.isEmpty ? "" : " " + unit
        if line.met { return String(localized: "careplan.outcome.met", defaultValue: "Reached") }
        guard let current = line.current, let target = line.target else {
            return String(localized: "careplan.outcome.open", defaultValue: "In progress")
        }
        if line.lowerIsBetter {
            return String(localized: "careplan.outcome.lower", defaultValue: "now \(number(current)) · target \(number(target))") + suffix
        }
        return String(localized: "careplan.outcome.of", defaultValue: "\(number(current)) of \(number(target))") + suffix
    }

    /// Whole-objective progress, 0…1: the practice's own `progress_pct` when it set one, else the mean of its outcomes.
    static func progress(_ objective: ClientObjective) -> Double? {
        if let pct = objective.progressPct { return min(max(Double(pct) / 100, 0), 1) }
        let all = lines(objective)
        guard !all.isEmpty else { return nil }
        return all.map(\.fraction).reduce(0, +) / Double(all.count)
    }

    /// "2 of 3 milestones" counts: outcomes met over outcomes that count.
    static func milestones(_ objective: ClientObjective) -> (met: Int, total: Int) {
        let all = lines(objective)
        return (all.filter(\.met).count, all.count)
    }

    /// The earliest due date among an objective's open outcomes (`YYYY-MM-DD`), else its target date.
    static func nextCheck(_ objective: ClientObjective) -> String? {
        let due = lines(objective).filter { !$0.met }.compactMap { $0.dueDate.map { String($0.prefix(10)) } }.min()
        return due ?? objective.targetDate.map { String($0.prefix(10)) }
    }

    /// The one objective nudge on Today: the first active objective with an outcome still open, and its nearest one.
    struct Nudge: Equatable, Sendable {
        let objectiveId: String
        let objectiveTitle: String
        let line: OutcomeLine
        /// "5 more days" when the outcome counts up to a target; nil otherwise.
        let remaining: String?
        let nextCheck: String?
    }

    static func nudge(_ raw: ClientCarePlanRaw) -> Nudge? {
        for objective in objectives(raw) where objective.status != "achieved" {
            let open = lines(objective).filter { !$0.met }
            // The line closest to done leads: it is the one a nudge can say "you are close" about.
            guard let lead = open.max(by: { $0.fraction < $1.fraction }) else { continue }
            var remaining: String?
            if !lead.lowerIsBetter, let current = lead.current, let target = lead.target, target > current {
                let unit = lead.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                remaining = String(localized: "careplan.nudge.more", defaultValue: "\(number(target - current)) more") + (unit.isEmpty ? "" : " " + unit)
            }
            return Nudge(objectiveId: objective.id, objectiveTitle: title(objective), line: lead, remaining: remaining, nextCheck: nextCheck(objective))
        }
        return nil
    }

    // MARK: Wins

    /// The most recent shared win (the RPC orders newest first; this does not trust that), with text.
    static func latestWin(_ raw: ClientCarePlanRaw) -> ClientWin? {
        wins(raw).first
    }

    /// Shared wins with words, newest first (undated last).
    static func wins(_ raw: ClientCarePlanRaw) -> [ClientWin] {
        raw.wins.enumerated()
            .filter { !($0.element.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
            .sorted { a, b in
                let da = a.element.achievedAt ?? "", db = b.element.achievedAt ?? ""
                if da != db { return da > db }
                return a.offset < b.offset
            }.map(\.element)
    }

    // MARK: Complaints, evolution and the mini curve

    enum ComplaintStatus: Equatable, Sendable {
        case managed, inProgress, notYet

        init(_ raw: String?) {
            switch raw {
            case "managed": self = .managed
            case "not_yet": self = .notYet
            default: self = .inProgress
            }
        }

        /// The three words the practice chose (Thomas, 2026-11-12): Managed / Being taken care of / Not yet managed.
        var label: String {
            switch self {
            case .managed: String(localized: "careplan.status.managed", defaultValue: "Managed")
            case .inProgress: String(localized: "careplan.status.inProgress", defaultValue: "Being taken care of")
            case .notYet: String(localized: "careplan.status.notYet", defaultValue: "Not yet managed")
            }
        }

        /// Status is never carried by colour alone (rule 10): each has its own symbol.
        var symbol: String {
            switch self {
            case .managed: "checkmark.circle.fill"
            case .inProgress: "arrow.triangle.2.circlepath"
            case .notYet: "circle.dashed"
            }
        }
    }

    /// A complaint's name: its label, else the signal key made readable.
    static func name(_ complaint: ClientComplaint) -> String {
        if let label = complaint.complaintLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
        return (complaint.signalKey ?? "").replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// The evolution entries that belong to a complaint: same signal key, else same label (case-insensitive).
    static func evolution(for complaint: ClientComplaint, in raw: ClientCarePlanRaw) -> [ClientEvolution] {
        let label = name(complaint).lowercased()
        return raw.evolution.filter { e in
            if let a = complaint.signalKey, !a.isEmpty, let b = e.signalKey, !b.isEmpty { return a == b }
            return !label.isEmpty && (e.complaintLabel ?? "").trimmingCharacters(in: .whitespaces).lowercased() == label
        }
    }

    /// "What helped" wording for a cause kind; the cause's own label is the practice's.
    static func causeKindLabel(_ kind: String?) -> String {
        switch kind {
        case "elimination": String(localized: "careplan.cause.elimination", defaultValue: "Elimination")
        case "reintroduction": String(localized: "careplan.cause.reintroduction", defaultValue: "Reintroduction")
        case "phase": String(localized: "careplan.cause.phase", defaultValue: "Phase")
        case "supplement": String(localized: "careplan.cause.supplement", defaultValue: "Supplement")
        case "other": String(localized: "careplan.cause.other", defaultValue: "Other")
        default: String(localized: "careplan.cause.action", defaultValue: "Action")
        }
    }

    static func directionLabel(_ direction: String?) -> String {
        switch direction {
        case "improved": String(localized: "careplan.direction.improved", defaultValue: "Improved")
        case "worsened": String(localized: "careplan.direction.worsened", defaultValue: "Worsened")
        default: String(localized: "careplan.direction.same", defaultValue: "No change")
        }
    }

    /// "4 → 7 /10": before and after when the practice measured both.
    static func beforeAfter(_ e: ClientEvolution) -> String? {
        guard let before = e.beforeValue, let after = e.afterValue else { return nil }
        let unit = e.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(number(before)) → \(number(after))" + (unit.isEmpty ? "" : " " + unit)
    }

    /// The check-in series a complaint's signal draws, from the day rows the app already loads (0…100, higher =
    /// better, oldest first). Only the signals the daily check-in actually holds draw a curve; anything else has none
    /// (rule 9: nothing is inferred). `signalKey` is matched loosely: energy · mood · sleep · calm/stress · digestion/gut/bloating.
    static func series(signalKey: String?, label: String? = nil, history: [DailyCheckin]) -> [Double] {
        let key = ((signalKey?.isEmpty == false ? signalKey : label) ?? "").lowercased()
        let pick: (DailyCheckin) -> Int?
        if key.contains("energy") || key.contains("fatigue") { pick = \.energy }
        else if key.contains("mood") { pick = \.mood }
        else if key.contains("sleep") { pick = \.sleep }
        else if key.contains("calm") || key.contains("stress") { pick = \.calmness }
        else if key.contains("gut") || key.contains("digest") || key.contains("bloat") { pick = \.gutOverall }
        else { return [] }
        let values = history.sorted { $0.day < $1.day }.compactMap(pick).map(Double.init)
        // A curve needs a shape: fewer than three points is a dot, not a trend.
        return values.count >= 3 ? values : []
    }

    // MARK: Today

    /// The members' "This week's focus" on Today: today's actions of the habits behind a weekly-focus care-plan item;
    /// with none flagged, the prescribed actions due today. Capped, in the day's order.
    static func focusActions(_ plan: HabitPlan, actions: [HabitAction], limit: Int = 3) -> [HabitAction] {
        let byId = Dictionary(plan.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let flagged = actions.filter { a in byId[a.id]?.carePlanItemId.map { plan.focusItemIds.contains($0) } ?? false }
        if !flagged.isEmpty { return Array(flagged.prefix(limit)) }
        return Array(actions.filter { byId[$0.id]?.isSelfInitiated == false }.prefix(limit))
    }
}
