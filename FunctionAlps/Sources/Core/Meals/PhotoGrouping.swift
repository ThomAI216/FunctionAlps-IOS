import Foundation

/// The app cannot know whether five photos are five meals or one dinner with five plates, and there is
/// nothing to cluster on (the picker hands over pixels, not timestamps). So it asks — once, immediately after
/// picking, while the photos are still on the member's mind. The Expo `photo-grouping.ts`.
enum MealPhotoGrouping {
    /// How many photos may belong to ONE meal — the edge function's `MAX_IDENTIFY_IMAGES`. A client that thinks
    /// the limit is five while the model is handed four sends a fifth plate nobody prices.
    static let maxPerMeal = 4
    /// The picker's ceiling. Above this the day-review flow is the right tool, and memory on an older phone is real.
    static let maxSelection = 12

    enum Choice: Sendable, Equatable {
        /// One photo (or none) — no question, today's path.
        case single
        /// Two or more — the app cannot know, so it asks.
        case ask
    }

    static func choice(for count: Int) -> Choice { count <= 1 ? .single : .ask }

    /// Whether "one meal" may be offered for this many photos. Above the cap the sheet still opens and still
    /// offers "separate meals" — refusing the combine is right, quietly analysing the first four is not.
    static func oneMealAllowed(_ count: Int) -> Bool { count >= 2 && count <= maxPerMeal }
}
