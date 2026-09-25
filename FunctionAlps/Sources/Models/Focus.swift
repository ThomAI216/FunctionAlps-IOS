import Foundation

/// Today's focus — `member-daily-focus`: the practice's own offer for this morning, then what the member said
/// the day is for, at the intensity their readiness can carry. Decided server-side (rule 9); the phone only shows
/// it and records "done". Stored in `habit_offers`, one row per offer per day.
struct TodayFocus: Sendable, Equatable, Decodable {
    /// `YYYY-MM-DD` — the member's own day (`patient_local_today`).
    let day: String
    /// No morning check-in yet today: the engine never guesses a day it was told nothing about.
    let needsCheckin: Bool
    /// Rank order: the first is the day's focus, the rest are "also today" (three at most).
    let offers: [FocusOffer]

    var focus: FocusOffer? { offers.first }
    var alsoToday: [FocusOffer] { Array(offers.dropFirst()) }
}

struct FocusOffer: Sendable, Equatable, Decodable, Identifiable {
    /// `habit_offers.id` — what "done" writes to.
    let id: String
    let offerKey: String
    let rank: Int?
    /// The practice's words, verbatim (`state_responses` / `habit_bank`).
    let title: String
    let description: String?
    let pillar: String?
    let slot: String?
    let variant: String?
    let reason: String?
    /// What put it there — a state key, a `day_priority` pill key, or `readiness_low`.
    let trigger: String
    /// The practice's heading for the state behind the focus ("A gentler start"), when there is one.
    let stateTitle: String?
    var accepted: Bool?
    var completed: Bool

    enum Reason: String, Sendable {
        case state, priority
        case readinessLow = "readiness_low"
        case recoverySupport = "recovery_support"
    }

    var reasonKind: Reason? { reason.flatMap(Reason.init(rawValue:)) }
    var pillarValue: Pillar? { pillar.flatMap(Pillar.init(rawValue:)) }
    /// The morning's priority pill behind this offer, when a priority put it there.
    var priority: CatalogPill? { PillCatalog.pill(trigger).flatMap { $0.group == .dayPriority ? $0 : nil } }
}
