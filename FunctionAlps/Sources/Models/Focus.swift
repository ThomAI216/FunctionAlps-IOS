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
    /// The day as the engine read it — nil until the morning check-in, or when the morning gave no band.
    /// Stored server-side once, so it holds still with the offers (`patient_day_state`).
    var readiness: FocusReadiness?

    var focus: FocusOffer? { offers.first }
    var alsoToday: [FocusOffer] { Array(offers.dropFirst()) }

    /// The language to ask for: the one this app is actually drawn in (`en` · `fr`), so the practice's words
    /// match the card around them. Not the phone's first language — a phone set to German, then French, shows
    /// this app in French, and must get the offers in French too.
    static func locale(_ localizations: [String] = Bundle.main.preferredLocalizations) -> String {
        localizations.first.map { $0.lowercased().hasPrefix("fr") ? "fr" : "en" } ?? "en"
    }
}

/// Low · mid · high — the check-in engine's own bands (<40, 40–60, >60), as `member-daily-focus` read the day.
enum ReadinessBand: String, Sendable, Equatable {
    case low, mid, high
}

/// The day's readiness as the server stored it: the band, whether a personal HRV baseline backs it (the only case
/// the app says "below your usual"), and where it came from (a wearable, or the member's own read of the night).
struct FocusReadiness: Sendable, Equatable, Decodable {
    let band: String
    let vsBaseline: Bool
    let source: String?

    var bandValue: ReadinessBand? { ReadinessBand(rawValue: band) }
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
