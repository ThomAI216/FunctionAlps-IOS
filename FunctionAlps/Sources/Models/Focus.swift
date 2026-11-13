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
    /// The matrix cell the day was decided on (`patient_day_state.focus_cell`): headline, line, tone, the practitioner line, the
    /// kickoff routine. Nil from a server that predates the matrix — the card then shows `offers` as before.
    var cell: FocusCell?

    var focus: FocusOffer? { offers.first }
    var alsoToday: [FocusOffer] { Array(offers.dropFirst()) }

    /// The same day with other offers (a tick is shown at once and written behind).
    func replacing(offers: [FocusOffer]) -> TodayFocus {
        TodayFocus(day: day, needsCheckin: needsCheckin, offers: offers, readiness: readiness, cell: cell)
    }

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
    /// The `habit_bank` card behind the offer (`bank:<id>` keys) — what a tap opens. Nil for a state offer of an older day.
    var cardId: String? = nil
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

    /// The card this offer opens: the server's `cardId`, else the one in a `bank:<id>` key.
    var bankCardId: String? { cardId ?? (offerKey.hasPrefix("bank:") ? String(offerKey.dropFirst(5)) : nil) }
    var reasonKind: Reason? { reason.flatMap(Reason.init(rawValue:)) }
    var pillarValue: Pillar? { pillar.flatMap(Pillar.init(rawValue:)) }
    /// The morning's priority pill behind this offer, when a priority put it there.
    var priority: CatalogPill? { PillCatalog.pill(trigger).flatMap { $0.group == .dayPriority ? $0 : nil } }
}

// MARK: - The matrix cell (owner-approved 2026-11-12)

/// How the Home card is drawn: go with it · a step further · steady · pace yourself · hold steady.
enum FocusTone: String, Sendable, Equatable {
    case go, peak, soft, care, rest
}

/// Today's focus as the server decided it: one cell of last night's sleep x how the member feels for the day. Every word is
/// the server's (rule 6): headline and line in the member's language, the practitioner line only when it applies (P5 and OG3,
/// after 3 or more depleted days in 7), and the kickoff morning routine on a short-night or depleted / flat morning.
struct FocusCell: Sendable, Equatable, Decodable {
    /// P1…P5 · O1 · OG1…OG3 · G1 · G2 (PX · GM when the feeling was skipped).
    let id: String
    let headline: String
    let line: String
    let tone: String
    /// "We'll look at it together with your practitioner." — nil unless it applies.
    let practitionerLine: String?
    /// A short night or a depleted / flat feeling: the evening check-in asks how the rest of the day went.
    let hardMorning: Bool
    /// The routine for a slow morning; nil when the cell does not offer it (or too few of its cards are open to this member).
    let kickoff: FocusKickoff?

    var toneKind: FocusTone { FocusTone(rawValue: tone) ?? .soft }
}

/// "Kickoff morning routine": the ordered steps (movement, breathing, light, connection & positivity, hydration, a high-protein
/// breakfast), each a real action card. The definition and every word live server-side.
struct FocusKickoff: Sendable, Equatable, Decodable {
    let key: String
    let title: String
    let subtitle: String
    let steps: [FocusKickoffStep]
    /// The last screen: a line of thanks, in the server's words.
    let finishTitle: String?
    let finishLine: String?
}

struct FocusKickoffStep: Sendable, Equatable, Decodable, Identifiable {
    /// movement · breathing · light · connection · hydration · protein
    let kind: String
    /// "Movement", "Breathing"… in the member's language.
    let label: String
    /// The `habit_bank` card the step is.
    let cardId: String
    let title: String
    let description: String?

    var id: String { cardId }
}
