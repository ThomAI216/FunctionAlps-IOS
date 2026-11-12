import Foundation

/// What the morning check-in says to the member once it is done (owner-validated 2026-11-12). Plain if-then on the three
/// "Feeling for the day" sliders — no AI. Each slider is 0–10 under the hood (the bar shows 0–100): low < 4, mid 4–6,
/// high >= 7. Rules run top to bottom, from the most specific to the least, and the FIRST match wins; the last rule is the
/// default and matches everything. A skipped slider is "any": it can never satisfy a rule that asks for a band, so an
/// unanswered morning never reads as a low or a high one. Pure — the words are `String(localized:)` keys (en + fr).
enum MorningBand: Sendable, Equatable {
    case low, mid, high

    /// Band of a 0–100 slider read; nil when the slider was skipped.
    static func of(_ value: Double?) -> MorningBand? {
        guard let value else { return nil }
        let tenths = min(100, max(0, value)) / 10
        if tenths < 4 { return .low }
        if tenths >= 7 { return .high }
        return .mid
    }
}

/// What a rule asks of one slider.
enum MorningRequirement: Sendable, Equatable {
    case any, low, mid, high

    func matches(_ value: Double?) -> Bool {
        switch self {
        case .any: return true
        case .low: return MorningBand.of(value) == .low
        case .mid: return MorningBand.of(value) == .mid
        case .high: return MorningBand.of(value) == .high
        }
    }
}

/// A small thing the end screen offers ("+ A 10-minute walk outside"). The label is the member-facing wording; `habitHint`
/// is only a search token for `SignalActionMatch` — the button opens the practice's own action-bank card when one matches,
/// else the bank itself, never a habit the app makes up.
enum MorningAction: String, Sendable, CaseIterable, Equatable {
    case walk10 = "walk_10"
    case daylight
    case breathwork5 = "breathwork_5"
    case nsdr10 = "nsdr_10"
    case nap15 = "nap_15"
    case meditation
    case friend
    case proteinBreakfast = "protein_breakfast"
    case hydration
    case onePriority = "one_priority"

    var label: String {
        switch self {
        case .walk10: String(localized: "morning.action.walk_10", defaultValue: "A 10-minute walk outside")
        case .daylight: String(localized: "morning.action.daylight", defaultValue: "Daylight within the hour")
        case .breathwork5: String(localized: "morning.action.breathwork_5", defaultValue: "Breathwork (5 min)")
        case .nsdr10: String(localized: "morning.action.nsdr_10", defaultValue: "NSDR (10 min)")
        case .nap15: String(localized: "morning.action.nap_15", defaultValue: "Power nap (15 min)")
        case .meditation: String(localized: "morning.action.meditation", defaultValue: "Meditation")
        case .friend: String(localized: "morning.action.friend", defaultValue: "Text a friend for a coffee")
        case .proteinBreakfast: String(localized: "morning.action.protein_breakfast", defaultValue: "A protein-rich breakfast")
        case .hydration: String(localized: "morning.action.hydration", defaultValue: "A big glass of water")
        case .onePriority: String(localized: "morning.action.one_priority", defaultValue: "Keep one priority, lighten the rest")
        }
    }

    /// The `SignalActionMatch.keywords` token that finds this action's card in the bank; nil = open the bank itself.
    var habitHint: String? {
        switch self {
        case .walk10: "walk"
        case .daylight: "daylight"
        case .breathwork5: "breathwork"
        case .nsdr10: "nsdr"
        case .nap15: "nap"
        case .meditation: "meditation"
        case .friend: "social"
        case .proteinBreakfast: "protein_breakfast"
        case .hydration: "hydration"
        case .onePriority: nil
        }
    }
}

struct MorningRule: Sendable, Equatable, Identifiable {
    let id: String
    let mood: MorningRequirement
    let energy: MorningRequirement
    let motivation: MorningRequirement
    let title: String
    let line: String
    let actions: [MorningAction]
    /// The warm (gold) mark for a morning that needs no help, the green one otherwise.
    var isCelebration = false

    func matches(mood m: Double?, energy e: Double?, motivation v: Double?) -> Bool {
        mood.matches(m) && energy.matches(e) && motivation.matches(v)
    }

    /// At most two buttons on the end screen.
    var offered: [MorningAction] { Array(actions.prefix(MorningRules.maxActions)) }
}

enum MorningRules {
    static let maxActions = 2
    static let defaultId = "default"

    /// The first rule that matches; the last rule is the default and always does.
    static func rule(mood: Double?, energy: Double?, motivation: Double?) -> MorningRule {
        all.first { $0.matches(mood: mood, energy: energy, motivation: motivation) } ?? all[all.count - 1]
    }

    /// The rule table, in matching order. Words: `morning-rules.json` (owner-validated mockup), en + fr in the catalog.
    static let all: [MorningRule] = [
        MorningRule(
            id: "all_low", mood: .low, energy: .low, motivation: .low,
            title: String(localized: "morning.rule.all_low.title", defaultValue: "Take care of yourself today"),
            line: String(localized: "morning.rule.all_low.line", defaultValue: "Go gently: breathe, move a little, and don’t hesitate to talk to a friend — maybe over a coffee."),
            actions: [.walk10, .friend, .breathwork5]),
        MorningRule(
            id: "mood_energy_low", mood: .low, energy: .low, motivation: .any,
            title: String(localized: "morning.rule.mood_energy_low.title", defaultValue: "Take care of yourself today"),
            line: String(localized: "morning.rule.mood_energy_low.line", defaultValue: "Mornings like this happen. Get some daylight, breathe slowly, and let someone know how you feel."),
            actions: [.daylight, .breathwork5, .friend]),
        MorningRule(
            id: "mood_motivation_low", mood: .low, energy: .any, motivation: .low,
            title: String(localized: "morning.rule.mood_motivation_low.title", defaultValue: "A heavy start — and that’s okay"),
            line: String(localized: "morning.rule.mood_motivation_low.line", defaultValue: "Pick one small thing for today, and share a moment with someone you like."),
            actions: [.friend, .onePriority, .walk10]),
        MorningRule(
            id: "energy_motivation_low", mood: .any, energy: .low, motivation: .low,
            title: String(localized: "morning.rule.energy_motivation_low.title", defaultValue: "A slow start — go easy"),
            line: String(localized: "morning.rule.energy_motivation_low.line", defaultValue: "Your body is asking for less today. Keep one priority and give yourself a real break."),
            actions: [.onePriority, .nap15, .hydration]),
        MorningRule(
            id: "energy_low_rest_good", mood: .high, energy: .low, motivation: .high,
            title: String(localized: "morning.rule.energy_low_rest_good.title", defaultValue: "Keep the motivation high"),
            line: String(localized: "morning.rule.energy_low_rest_good.line", defaultValue: "You’ll get through this dip. A short power nap can help — and a few quiet minutes before it."),
            actions: [.nsdr10, .breathwork5, .nap15]),
        MorningRule(
            id: "energy_low", mood: .any, energy: .low, motivation: .any,
            title: String(localized: "morning.rule.energy_low.title", defaultValue: "Low on energy — be kind to yourself"),
            line: String(localized: "morning.rule.energy_low.line", defaultValue: "Start with water, light and a proper breakfast. A short reset later can help."),
            actions: [.nsdr10, .daylight, .proteinBreakfast]),
        MorningRule(
            id: "mood_low", mood: .low, energy: .any, motivation: .any,
            title: String(localized: "morning.rule.mood_low.title", defaultValue: "Be gentle with yourself today"),
            line: String(localized: "morning.rule.mood_low.line", defaultValue: "You have the energy — use some of it for something that feels kind: air, light or a friendly voice."),
            actions: [.breathwork5, .daylight, .friend]),
        MorningRule(
            id: "motivation_low", mood: .any, energy: .any, motivation: .low,
            title: String(localized: "morning.rule.motivation_low.title", defaultValue: "Start small"),
            line: String(localized: "morning.rule.motivation_low.line", defaultValue: "Motivation often follows action. Pick one easy thing and begin there."),
            actions: [.onePriority, .walk10, .meditation]),
        MorningRule(
            id: "all_high", mood: .high, energy: .high, motivation: .high,
            title: String(localized: "morning.rule.all_high.title", defaultValue: "You’re set for an amazing day."),
            line: String(localized: "morning.rule.all_high.line", defaultValue: "Make it count."),
            actions: [], isCelebration: true),
        MorningRule(
            id: "energy_mid", mood: .any, energy: .mid, motivation: .any,
            title: String(localized: "morning.rule.energy_mid.title", defaultValue: "A steady start"),
            line: String(localized: "morning.rule.energy_mid.line", defaultValue: "A little daylight and a glass of water can lift the morning even more."),
            actions: [.daylight, .hydration, .proteinBreakfast]),
        MorningRule(
            id: "mood_motivation_mid", mood: .mid, energy: .high, motivation: .any,
            title: String(localized: "morning.rule.mood_motivation_mid.title", defaultValue: "Good energy to use"),
            line: String(localized: "morning.rule.mood_motivation_mid.line", defaultValue: "You’re running well. Spend it on something that matters to you today."),
            actions: [.walk10, .meditation]),
        MorningRule(
            id: "default", mood: .any, energy: .any, motivation: .any,
            title: String(localized: "morning.rule.default.title", defaultValue: "Good morning — you’ve got this"),
            line: String(localized: "morning.rule.default.line", defaultValue: "A solid base for the day. Keep it simple and enjoy it."),
            actions: [.daylight]),
    ]
}
