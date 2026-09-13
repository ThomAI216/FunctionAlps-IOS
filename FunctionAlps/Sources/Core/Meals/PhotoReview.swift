import Foundation

/// Should the photo flow STOP and ask, before the analysis page? Only when the model was unsure (the owner's
/// call, 2026-08-21) — the Expo `lib/meal-log/photo-review.ts`. Two signals survive to the client on every
/// path: `analysis_coverage = 'partial'` and a `needs_review` item; the model's self-reported confidence is
/// measured dead (0.95 on 12 of 13 rows) and is not stored on the row.
enum PhotoReview {
    enum Reason: Sendable, Equatable { case partialCoverage, unidentifiedFood }

    static func reason(for meal: MealLog) -> Reason? {
        guard !meal.items.isEmpty else { return nil }
        if meal.analysisCoverage == "partial" { return .partialCoverage }
        if meal.items.contains(where: \.needsReview) { return .unidentifiedFood }
        return nil
    }

    /// One sentence naming what we are unsure about.
    static func copy(_ reason: Reason) -> String {
        switch reason {
        case .partialCoverage:
            String(localized: "photoReview.partial", defaultValue: "We could not see the whole plate · check the portions before we count them.")
        case .unidentifiedFood:
            String(localized: "photoReview.unidentified", defaultValue: "One of these is not in our food database · check the portions, and rename anything we got wrong.")
        }
    }
}
