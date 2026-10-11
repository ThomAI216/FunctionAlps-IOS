import Foundation

/// The launch switch for "The FunctionAlps Show" in the Library.
///
/// Owner's decision (Thomas, 2026-10-06): "for the episodes, we are going to take a step back. We are not going to
/// publish all of this… I just want these parts to be blurred and 'Coming soon'." While `comingSoon` is true:
/// - the Library shows the show as a blurred, wordless preview under a "Coming soon" note (no CLINICAL call);
/// - no episode can be opened (links and taps land on the Library);
/// - experiment marks are never written and no daily reminder is planned;
/// - reminders a tester scheduled on build 55 (`show.exp.*`) are cancelled at launch.
/// Set it to false and everything behaves as shipped on 2026-10-03.
enum ShowFeature {
    static let comingSoon = true

    /// What the Library's show section is.
    enum Presentation: Equatable {
        /// The blurred preview + "Coming soon".
        case comingSoon
        /// The real section, from the loaded show data.
        case live
        /// No show data (any failure): the section is not there.
        case hidden
    }

    static func presentation(comingSoon: Bool = ShowFeature.comingSoon, hasData: Bool) -> Presentation {
        if comingSoon { return .comingSoon }
        return hasData ? .live : .hidden
    }

    /// Whether `functionalps://library/show/<slug>` (or an in-app tap) may open an episode.
    static func episodesReachable(comingSoon: Bool = ShowFeature.comingSoon) -> Bool { !comingSoon }

    /// The reminder plan, or nothing at all while the show is coming soon.
    static func reminderPlan(comingSoon: Bool = ShowFeature.comingSoon, days: [Int], state: ShowLogic.ExperimentState,
                             now: Date, calendar: Calendar) -> [(day: Int, fireAt: Date)] {
        guard !comingSoon else { return [] }
        return ShowLogic.reminderPlan(days: days, state: state, now: now, calendar: calendar)
    }

    /// The pending / delivered notification ids that belong to show experiments (to cancel while coming soon).
    static func showReminderIDs(in ids: [String]) -> [String] {
        ids.filter { $0.hasPrefix(ShowLogic.reminderPrefix) }
    }
}
