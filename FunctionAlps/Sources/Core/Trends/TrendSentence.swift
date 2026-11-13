import Foundation

/// How a signal's last days compare with its own window — the four reads the Trends sentence can make.
enum TrendKind: String, Sendable, Equatable, CaseIterable {
    case steady, rising, dipped, notEnoughData
}

/// The one-line read under a signal on Trends ("Your energy has been steady this week, keep it up.").
///
/// ⚠ THE WORDING SET IS FIXED AND APPROVED BY THE OWNER (2026-11-12). A sentence is chosen from this closed
/// table — six signals × {steady, rising, dipped} plus one "not enough data" line — by a pure function of the
/// member's own daily series. Nothing is generated, nothing interprets a value clinically, and a "dipped" line
/// only ever says it will be looked at WITH the practitioner. Do not add a sentence without the owner's sign-off.
///
/// FOLLOW-UP (CLAUDE.md rule 9, "business/health calculations stay server-side"): the classification below is a
/// count and an average on the phone — within the "Swift may count, average, format" allowance — but the margin
/// and the three-day rule are a product decision that belongs in an edge function so every client agrees to the
/// word. Tracked in docs/IOS_MIGRATION_MAP.md ("Trends rework").
enum TrendSentence {
    /// Fewer logged days than this in the window and there is no trend to read.
    static let minimumDays = 4
    /// "The last 3 days" — compared with the window's own average.
    static let recentDays = 3
    /// How far, on the 0–100 marker, the last days must sit from the window average to count as a move.
    static let margin = 8.0

    /// `goodness` is the signal's daily marker over the window, OLDEST FIRST, nil = not logged, on the app's
    /// 0–100 scale where HIGHER IS BETTER. Stress is the CALMNESS marker (see the MARKER CONTRACT in
    /// Models/Checkin.swift), so a "dipped" stress series is a rise in stress — the stress sentence says so.
    static func classify(_ goodness: [Double?]) -> TrendKind {
        let present = goodness.compactMap { $0 }
        guard present.count >= minimumDays else { return .notEnoughData }
        let average = present.reduce(0, +) / Double(present.count)
        let recent = goodness.suffix(recentDays).compactMap { $0 }
        guard recent.count >= 2 else { return .steady }
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        if recentMean <= average - margin { return .dipped }
        if recentMean >= average + margin { return .rising }
        return .steady
    }

    static func sentence(for signal: TrendSignal, goodness: [Double?]) -> String {
        text(for: signal, kind: classify(goodness))
    }

    static func text(for signal: TrendSignal, kind: TrendKind) -> String {
        switch (signal, kind) {
        case (_, .notEnoughData):
            return String(localized: "trends.sentence.none", defaultValue: "Not enough check-ins yet to see a trend. A few more days and it will show here.")
        case (.sleep, .steady):
            return String(localized: "trends.sentence.sleep.steady", defaultValue: "Your sleep has been steady this week, keep it up.")
        case (.sleep, .rising):
            return String(localized: "trends.sentence.sleep.rising", defaultValue: "Your sleep has been improving these last days.")
        case (.sleep, .dipped):
            return String(localized: "trends.sentence.sleep.dipped", defaultValue: "Your sleep dipped the last 3 days — we'll look at it with your practitioner.")
        case (.energy, .steady):
            return String(localized: "trends.sentence.energy.steady", defaultValue: "Your energy has been steady this week, keep it up.")
        case (.energy, .rising):
            return String(localized: "trends.sentence.energy.rising", defaultValue: "Your energy has been on the rise these last days.")
        case (.energy, .dipped):
            return String(localized: "trends.sentence.energy.dipped", defaultValue: "Your energy dipped the last 3 days — we'll look at it with your practitioner.")
        case (.focus, .steady):
            return String(localized: "trends.sentence.focus.steady", defaultValue: "Your focus has been steady this week, keep it up.")
        case (.focus, .rising):
            return String(localized: "trends.sentence.focus.rising", defaultValue: "Your focus has been on the rise these last days.")
        case (.focus, .dipped):
            return String(localized: "trends.sentence.focus.dipped", defaultValue: "Your focus dipped the last 3 days — we'll look at it with your practitioner.")
        case (.mood, .steady):
            return String(localized: "trends.sentence.mood.steady", defaultValue: "Your mood has been steady this week, keep it up.")
        case (.mood, .rising):
            return String(localized: "trends.sentence.mood.rising", defaultValue: "Your mood has been on the rise these last days.")
        case (.mood, .dipped):
            return String(localized: "trends.sentence.mood.dipped", defaultValue: "Your mood dipped the last 3 days — we'll look at it with your practitioner.")
        case (.stress, .steady):
            return String(localized: "trends.sentence.stress.steady", defaultValue: "Your stress has been steady this week.")
        case (.stress, .rising):
            return String(localized: "trends.sentence.stress.rising", defaultValue: "Your stress has been easing these last days.")
        case (.stress, .dipped):
            return String(localized: "trends.sentence.stress.dipped", defaultValue: "Your stress was higher the last 3 days — we'll look at it with your practitioner.")
        case (.digestion, .steady):
            return String(localized: "trends.sentence.digestion.steady", defaultValue: "Your digestion has been steady this week, keep it up.")
        case (.digestion, .rising):
            return String(localized: "trends.sentence.digestion.rising", defaultValue: "Your digestion has been feeling better these last days.")
        case (.digestion, .dipped):
            return String(localized: "trends.sentence.digestion.dipped", defaultValue: "A couple of uncomfortable days this week — your practitioner will review them with you.")
        }
    }
}
