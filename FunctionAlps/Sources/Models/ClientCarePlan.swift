import Foundation

// The client's care plan (CLINICAL 2026-11-12, migrations 325 + 331): what the practice has decided to share, read
// through seven member RPCs on CM OS (`member_care_plan_*`). Members have NO table access behind them: each RPC is
// SECURITY DEFINER, keyed on the signed-in member, and returns only what a clinician explicitly shared (or, for
// programmes and objectives, what is approved). Nothing here is computed from a health signal and no clinical
// wording is written in Swift: every sentence below is the practice's, as the RPC returned it (rule 6, rule 9).
//
// Rows decode with `convertFromSnakeCase`, so a column `client_verbatim` is `clientVerbatim`; every optional is
// optional on purpose — a missing column must degrade a line, never fail the whole plan.

/// One phase of a programme (`member_care_plan_programmes.phases[]`).
struct ClientPhase: Decodable, Sendable, Equatable {
    let title: String?
    let weekStart: Int?
    let weekEnd: Int?
    let sortOrder: Int?
}

/// `member_care_plan_programmes()` — structure only: title, dates, planned weeks, its phases.
struct ClientProgramme: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let kind: String?
    let title: String?
    /// `planned` · `active` · `completed` (a set-aside programme never arrives).
    let status: String?
    let startDate: String?
    let endDate: String?
    let plannedWeeks: Int?
    let position: Int?
    let phases: [ClientPhase]?

    var isActive: Bool { status == "active" }
}

/// One measurable outcome of an objective (`member_care_plan_objectives.outcomes[]`, `care_plan_goal_outcomes`).
struct ClientOutcome: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let label: String?
    let metricKey: String?
    /// `<` · `>` · `=` · `<=` · `>=`
    let comparator: String?
    let targetValue: Double?
    let baselineValue: Double?
    let currentValue: Double?
    let unit: String?
    let dueDate: String?
    /// `open` · `met` · `missed` (a dropped outcome never arrives).
    let status: String?
    let metAt: String?
}

/// `member_care_plan_objectives()` — approved, patient-visible goals, in the client's own words when the practice kept them.
struct ClientObjective: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let programmeId: String?
    let clientVerbatim: String?
    let statement: String?
    let targetDate: String?
    let progressPct: Int?
    /// `active` · `achieved`
    let status: String?
    let outcomes: [ClientOutcome]?
}

/// `member_care_plan_wins()` — a win the practice shared.
struct ClientWin: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let programmeId: String?
    let programmeTitle: String?
    let kind: String?
    let text: String?
    let status: String?
    let achievedAt: String?
    let sharedAt: String?
}

/// `member_care_plan_complaints()` — one shared complaint with its status and the practice's one-line summary.
struct ClientComplaint: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let programmeId: String?
    let signalKey: String?
    let complaintLabel: String?
    /// `managed` · `in_progress` · `not_yet`
    let status: String?
    let clientSummary: String?
    let sharedAt: String?
}

/// `member_care_plan_hypotheses()` — "why we're doing this": a kept, shared hypothesis in the client's words.
struct ClientHypothesis: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let programmeId: String?
    let title: String?
    let explanation: String?
    let howWeKnow: String?
    /// `[{ kind, title, url }]`, read leniently (a malformed entry reads as no link).
    let resources: HabitLinks?
    let lifecycle: String?
    let lifecycleAt: String?
    let proposedByFirstName: String?
    let sharedAt: String?
}

/// `member_care_plan_evolution()` — a validated, shared link between something that was done and what changed.
struct ClientEvolution: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let programmeId: String?
    let signalKey: String?
    let complaintLabel: String?
    /// `action` · `elimination` · `reintroduction` · `phase` · `supplement` · `other`
    let causeKind: String?
    let causeLabel: String?
    let beforeFrom: String?
    let beforeTo: String?
    let afterFrom: String?
    let afterTo: String?
    let beforeValue: Double?
    let afterValue: Double?
    let unit: String?
    /// `improved` · `worsened` · `no_change`
    let direction: String?
    let clientText: String?
    let validatedAt: String?
    let sharedAt: String?
}

/// `member_care_plan_situation()` — where the client started, in the practice's words. (`baseline` jsonb is not read.)
struct ClientSituation: Decodable, Sendable, Equatable {
    let programmeId: String?
    let title: String?
    let kind: String?
    let status: String?
    let startDate: String?
    let situationText: String?
    let sharedAt: String?
}

/// The seven reads in one value. Only programmes and objectives may fail the load; the rest are extras that fail
/// soft to empty (see `SupabaseBackend.clientCarePlan`).
struct ClientCarePlanRaw: Sendable, Equatable {
    var programmes: [ClientProgramme] = []
    var objectives: [ClientObjective] = []
    var wins: [ClientWin] = []
    var complaints: [ClientComplaint] = []
    var hypotheses: [ClientHypothesis] = []
    var evolution: [ClientEvolution] = []
    var situation: [ClientSituation] = []

    static let empty = ClientCarePlanRaw()

    /// Nothing the practice has shared yet — the screens fall back to the existing plan page.
    var isEmpty: Bool {
        programmes.isEmpty && objectives.isEmpty && wins.isEmpty && complaints.isEmpty && hypotheses.isEmpty && situation.isEmpty
    }
}
