import Foundation
import SwiftUI

/// The explainer page's copy, one template for the three scores — the Expo `score-explainers.ts` + its French
/// overlay, ported string for string. ⚠ LEGAL SURFACE: every line describes the MEAL and its nutritional
/// characteristics, never the member's body (score-rename-brief). The keys stay `inflammation` / `glycemic` /
/// `digestion` because they are the DB columns; nothing here prints a key.
struct ScoreExplainerCopy: Sendable {
    let kind: MealScoreKind
    let label: String
    let color: Color
    let subtitle: String
    /// The static "why it matters" — the fallback when nothing is known about the member yet.
    let whyForYou: String
    let tips: [String]
    let congrats: String
    let whatItIs: String
    let upLabel: String
    let downLabel: String
    let up: [String]
    let down: [String]
    let science: String

    static func copy(for kind: MealScoreKind) -> ScoreExplainerCopy {
        switch kind {
        case .digestion:
            return ScoreExplainerCopy(
                kind: kind,
                label: String(localized: "score.digestion.title", defaultValue: "Plants & Fibre"),
                color: FAColor.scoreDigestion,
                subtitle: String(localized: "scoreX.digestion.subtitle", defaultValue: "How much fibre and plant variety this meal contains."),
                whyForYou: String(localized: "scoreX.digestion.why", defaultValue: "Most meals draw their fibre from one or two foods. Adding a third or fourth plant is usually the easiest change to make."),
                tips: [
                    String(localized: "scoreX.digestion.tip0", defaultValue: "Add one more vegetable rather than more of the same one."),
                    String(localized: "scoreX.digestion.tip1", defaultValue: "Add lentils, chickpeas or beans · they lift fibre and plant count together."),
                    String(localized: "scoreX.digestion.tip2", defaultValue: "Scatter nuts or seeds over what you already made."),
                ],
                congrats: String(localized: "scoreX.digestion.congrats", defaultValue: "A fibre-rich plate drawing on several different plants."),
                whatItIs: String(localized: "scoreX.digestion.whatItIs", defaultValue: "This score describes two things about the meal you recorded: how much fibre it contains, and how many different plant foods contributed. Vegetables, fruit, legumes, whole grains, nuts and seeds each bring different fibres, so variety counts alongside the total."),
                upLabel: String(localized: "scoreX.liftsIt", defaultValue: "Lifts it"),
                downLabel: String(localized: "scoreX.limitsIt", defaultValue: "Limits it"),
                up: [
                    String(localized: "scoreX.digestion.up0", defaultValue: "Legumes & pulses"),
                    String(localized: "scoreX.digestion.up1", defaultValue: "Several different vegetables"),
                    String(localized: "scoreX.digestion.up2", defaultValue: "Whole grains"),
                    String(localized: "scoreX.digestion.up3", defaultValue: "Nuts & seeds"),
                ],
                down: [
                    String(localized: "scoreX.digestion.down0", defaultValue: "One plant food only"),
                    String(localized: "scoreX.digestion.down1", defaultValue: "Refined grains"),
                    String(localized: "scoreX.digestion.down2", defaultValue: "No vegetables recorded"),
                    String(localized: "scoreX.digestion.down3", defaultValue: "Plants as a garnish"),
                ],
                science: String(localized: "scoreX.digestion.science", defaultValue: "Fibre intake across populations is consistently associated with better long-term outcomes; the WHO-commissioned Reynolds 2019 review of 185 studies found the clearest benefits at 25-29 g a day. This score describes the food, not your digestion or gut health.")
            )
        case .inflammation:
            return ScoreExplainerCopy(
                kind: kind,
                label: String(localized: "score.inflammation.title", defaultValue: "Fat Quality"),
                color: FAColor.scoreInflammation,
                subtitle: String(localized: "scoreX.inflammation.subtitle", defaultValue: "Where the fat in this meal comes from · the sources, not the amount."),
                whyForYou: String(localized: "scoreX.inflammation.why", defaultValue: "Fat quality moves with the sources on the plate rather than the total. Meals built around olive oil, nuts and oily fish sit at the top of this range."),
                tips: [
                    String(localized: "scoreX.inflammation.tip0", defaultValue: "Cook with olive or rapeseed oil rather than a hard cooking fat."),
                    String(localized: "scoreX.inflammation.tip1", defaultValue: "Add nuts, seeds or avocado · they raise this score even though they raise total fat."),
                    String(localized: "scoreX.inflammation.tip2", defaultValue: "Choose oily fish once or twice a week for the omega-3 contribution."),
                ],
                congrats: String(localized: "scoreX.inflammation.congrats", defaultValue: "The fat in this meal comes mostly from whole-food sources."),
                whatItIs: String(localized: "scoreX.inflammation.whatItIs", defaultValue: "This score describes which foods the fat in the meal came from, and what kind of fat they carry. Total fat is deliberately excluded: a handful of walnuts is almost entirely fat and scores well, while a low-fat biscuit does not. The question is what kind, not how much."),
                upLabel: String(localized: "scoreX.limitsIt", defaultValue: "Limits it"),
                downLabel: String(localized: "scoreX.liftsIt", defaultValue: "Lifts it"),
                up: [
                    String(localized: "scoreX.inflammation.up0", defaultValue: "Deep-fried foods"),
                    String(localized: "scoreX.inflammation.up1", defaultValue: "Cured & processed meats"),
                    String(localized: "scoreX.inflammation.up2", defaultValue: "Confectionery"),
                    String(localized: "scoreX.inflammation.up3", defaultValue: "Hard cooking fats"),
                ],
                down: [
                    String(localized: "scoreX.inflammation.down0", defaultValue: "Olive & rapeseed oil"),
                    String(localized: "scoreX.inflammation.down1", defaultValue: "Nuts, seeds & avocado"),
                    String(localized: "scoreX.inflammation.down2", defaultValue: "Oily fish"),
                    String(localized: "scoreX.inflammation.down3", defaultValue: "Fresh whole foods"),
                ],
                science: String(localized: "scoreX.inflammation.science", defaultValue: "PREDIMED randomised participants to a Mediterranean diet with extra olive oil or nuts against a low-fat control, and the higher-fat arms fared better · evidence that fat source matters more than fat quantity. This score describes the meal, not your cholesterol or cardiovascular risk.")
            )
        case .glycemic:
            return ScoreExplainerCopy(
                kind: kind,
                label: String(localized: "score.glycemic.title", defaultValue: "Carb Quality"),
                color: FAColor.scoreGlycemic,
                subtitle: String(localized: "scoreX.glycemic.subtitle", defaultValue: "How much of the carbohydrate arrives with its fibre intact."),
                whyForYou: String(localized: "scoreX.glycemic.why", defaultValue: "Intact carbohydrate sources · whole grains, legumes, whole fruit · carry their fibre with them. Refined flour and sweetened drinks largely do not."),
                tips: [
                    String(localized: "scoreX.glycemic.tip0", defaultValue: "Choose an intact grain: whole-grain bread, brown rice, oats."),
                    String(localized: "scoreX.glycemic.tip1", defaultValue: "Add a legume to raise the fibre-to-carbohydrate ratio directly."),
                    String(localized: "scoreX.glycemic.tip2", defaultValue: "Eat fruit whole rather than as juice."),
                ],
                congrats: String(localized: "scoreX.glycemic.congrats", defaultValue: "The carbohydrate here arrives largely with its fibre intact."),
                whatItIs: String(localized: "scoreX.glycemic.whatItIs", defaultValue: "This score describes the FORM the carbohydrate took: the ratio of fibre to carbohydrate, how much came from intact sources, and an estimate of sugar from sweetened foods. Sugar inside whole fruit, vegetables and plain dairy is not counted against the meal."),
                upLabel: String(localized: "scoreX.limitsIt", defaultValue: "Limits it"),
                downLabel: String(localized: "scoreX.liftsIt", defaultValue: "Lifts it"),
                up: [
                    String(localized: "scoreX.glycemic.up0", defaultValue: "White bread & rice"),
                    String(localized: "scoreX.glycemic.up1", defaultValue: "Sweetened drinks & juice"),
                    String(localized: "scoreX.glycemic.up2", defaultValue: "Confectionery"),
                    String(localized: "scoreX.glycemic.up3", defaultValue: "Refined, low-fibre foods"),
                ],
                down: [
                    String(localized: "scoreX.glycemic.down0", defaultValue: "Whole grains"),
                    String(localized: "scoreX.glycemic.down1", defaultValue: "Legumes & pulses"),
                    String(localized: "scoreX.glycemic.down2", defaultValue: "Whole fruit"),
                    String(localized: "scoreX.glycemic.down3", defaultValue: "Vegetables alongside a starch"),
                ],
                science: String(localized: "scoreX.glycemic.science", defaultValue: "A food carrying at least 1 g of fibre per 10 g of carbohydrate is behaving like an intact whole food · the widely used 10:1 rule. This is a food-composition estimate, not a measurement or prediction of your individual blood glucose response.")
            )
        }
    }
}

/// The mandatory wording. Verbatim from the legal pack (07_SAFETY_ACCURACY_DISCLAIMERS.md) — do not paraphrase,
/// shorten or reword. `aboutBody` must appear on EVERY surface that shows a score, not only in Terms.
enum ScoreLegal {
    static var aboutTitle: String { String(localized: "score.about.title", defaultValue: "About this score") }
    static var aboutBody: String {
        String(localized: "score.about.body", defaultValue: "This score describes selected characteristics of the recorded meal. It does not measure or diagnose your body's inflammation, blood glucose, gut health or another medical condition.")
    }
    /// Attached wherever Carb Quality appears.
    static var carbNote: String {
        String(localized: "score.carbNote", defaultValue: "This is a food-composition estimate based on the carbohydrate and fibre recorded in the meal. It is not a measurement or prediction of your individual blood glucose response.")
    }
    /// Wherever a score carries low data confidence.
    static var lowConfidenceNote: String {
        String(localized: "score.lowConfidence", defaultValue: "Some foods in this meal could not be matched precisely to our reference data, so this score is an approximation. Correcting the ingredients will sharpen it.")
    }
}
