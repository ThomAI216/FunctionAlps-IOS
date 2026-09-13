import Foundation

/// "Why it matters for you" and "Make it even better" from what the app actually knows about the member: their
/// ranked objectives (`health_goals`, up to two cluster keys) and their REAL 7-day average + trend. Honest by
/// construction — every sentence is derived from data held; with no goals and no data the screen falls back to
/// the static copy. The Expo `score-personalization.ts`, rules-first.
///
/// Two rules govern every string: describe the FOOD and what it is generally associated with, never what is
/// happening inside this member; and every tip must move the score it is filed under.
enum ScorePersonalization {
    struct Context: Sendable, Equatable {
        var avg: Int?
        var trend: ScoreHistory.Trend?
    }

    // MARK: Why it matters

    private static func goalLink(_ kind: MealScoreKind, _ objective: String) -> String? {
        switch (kind, objective) {
        case (.glycemic, "energy"): String(localized: "scoreP.glycemic.energy", defaultValue: "Carbohydrate eaten with its fibre intact is a common starting point when steady energy is the goal.")
        case (.glycemic, "weight_metabolism"): String(localized: "scoreP.glycemic.weight", defaultValue: "Whole-food carbohydrate sources are central to most dietary patterns built around metabolic health.")
        case (.glycemic, "mind"): String(localized: "scoreP.glycemic.mind", defaultValue: "Intact carbohydrate sources are a frequent first change when people are working on focus through the day.")
        case (.glycemic, "sleep"): String(localized: "scoreP.glycemic.sleep", defaultValue: "Evening meals built on whole-food carbohydrate are a common adjustment when sleep is the goal.")
        case (.glycemic, "resilience"): String(localized: "scoreP.glycemic.resilience", defaultValue: "Whole grains and legumes are staples of the dietary patterns most associated with resilience.")
        case (.inflammation, "resilience"): String(localized: "scoreP.inflammation.resilience", defaultValue: "Whole-food fat sources · olive oil, nuts, oily fish · are characteristic of the patterns studied for recovery.")
        case (.inflammation, "age_well"): String(localized: "scoreP.inflammation.ageWell", defaultValue: "Fat source and quality are among the most consistently studied dietary factors in healthy ageing.")
        case (.inflammation, "strong_body"): String(localized: "scoreP.inflammation.strongBody", defaultValue: "Omega-3-bearing foods are a common addition to eating patterns built around training and recovery.")
        case (.inflammation, "gut"): String(localized: "scoreP.inflammation.gut", defaultValue: "Whole-food fat sources tend to arrive alongside fibre and plants rather than in place of them.")
        case (.inflammation, "hormones"): String(localized: "scoreP.inflammation.hormones", defaultValue: "Fats are the raw material for hormone synthesis, so their food sources are worth attention.")
        case (.inflammation, "energy"): String(localized: "scoreP.inflammation.energy", defaultValue: "Fat source is a useful thing to look at when building meals for the day ahead.")
        case (.digestion, "gut"): String(localized: "scoreP.digestion.gut", defaultValue: "Fibre and plant variety are the meal characteristics most directly relevant to this goal.")
        case (.digestion, "energy"): String(localized: "scoreP.digestion.energy", defaultValue: "Fibre-rich meals drawing on several plants are a common feature of energy-focused eating patterns.")
        case (.digestion, "sleep"): String(localized: "scoreP.digestion.sleep", defaultValue: "A varied, fibre-rich day is a frequent recommendation alongside work on sleep.")
        case (.digestion, "mind"): String(localized: "scoreP.digestion.mind", defaultValue: "Plant variety and fibre are the composition factors most studied alongside cognitive outcomes.")
        case (.digestion, "hormones"): String(localized: "scoreP.digestion.hormones", defaultValue: "Fibre and plant diversity are staples of the dietary patterns studied for hormonal health.")
        default: nil
        }
    }

    private static func baseSentence(_ kind: MealScoreKind) -> String {
        switch kind {
        case .glycemic: String(localized: "scoreP.base.glycemic", defaultValue: "This score reflects how much of your carbohydrate arrives with its fibre intact.")
        case .inflammation: String(localized: "scoreP.base.inflammation", defaultValue: "This score reflects where the fat in your meals has been coming from.")
        case .digestion: String(localized: "scoreP.base.digestion", defaultValue: "This score reflects the fibre and plant variety in the meals you log.")
        }
    }

    /// The trend sentence, translated as a whole phrase with the number filled in after lookup.
    static func trendSentence(_ ctx: Context) -> String? {
        guard let avg = ctx.avg else { return nil }
        switch ctx.trend {
        case .up: return String(localized: "scoreP.trend.up", defaultValue: "Your 7-day average is \(avg) and climbing · it's working.")
        case .down: return String(localized: "scoreP.trend.down", defaultValue: "Your 7-day average slipped to \(avg) this week · the tips below are where to look.")
        case .flat: return String(localized: "scoreP.trend.flat", defaultValue: "Your 7-day average is holding at \(avg).")
        case nil: return String(localized: "scoreP.trend.none", defaultValue: "Your 7-day average so far is \(avg).")
        }
    }

    /// Nil when nothing is known about the member yet — the caller shows the static copy.
    static func whyItMatters(_ kind: MealScoreKind, objectives: [String], _ ctx: Context) -> String? {
        let base: String
        if let link = objectives.lazy.compactMap({ goalLink(kind, $0) }).first {
            base = link
        } else if ctx.avg != nil {
            base = baseSentence(kind)
        } else {
            return nil
        }
        if let t = trendSentence(ctx) { return base + " " + t }
        return base
    }

    // MARK: Tips

    private struct Rule {
        let text: String
        var objectives: [String]? = nil
        var maxAvg: Int? = nil
        var trend: ScoreHistory.Trend? = nil
        var conditional: Bool { objectives != nil || maxAvg != nil || trend != nil }

        func matches(_ objectives: [String], _ ctx: Context) -> Bool {
            if let need = self.objectives, !need.contains(where: objectives.contains) { return false }
            if let maxAvg { guard let avg = ctx.avg, avg < maxAvg else { return false } }
            if let trend, ctx.trend != trend { return false }
            return true
        }
    }

    private static func bank(_ kind: MealScoreKind) -> [Rule] {
        switch kind {
        case .glycemic: [
            Rule(text: String(localized: "scoreT.glycemic.0", defaultValue: "Swap a refined grain for an intact one · brown rice, whole-grain bread, oats.")),
            Rule(text: String(localized: "scoreT.glycemic.1", defaultValue: "Add lentils or beans · they raise the fibre-to-carbohydrate ratio directly.")),
            Rule(text: String(localized: "scoreT.glycemic.2", defaultValue: "Eat fruit whole rather than as juice · the fibre stays in."), maxAvg: 70),
            Rule(text: String(localized: "scoreT.glycemic.3", defaultValue: "Add vegetables alongside a starch · more fibre, little extra carbohydrate."), objectives: ["energy", "weight_metabolism"]),
            Rule(text: String(localized: "scoreT.glycemic.4", defaultValue: "Replace a sweetened drink with water or unsweetened tea · the single largest move on this score."), maxAvg: 60, trend: .down),
            Rule(text: String(localized: "scoreT.glycemic.5", defaultValue: "Choose an unsweetened breakfast · sweetened cereals and spreads weigh most here."), objectives: ["mind", "sleep"]),
        ]
        case .inflammation: [
            Rule(text: String(localized: "scoreT.inflammation.0", defaultValue: "Cook with olive or rapeseed oil rather than a hard cooking fat.")),
            Rule(text: String(localized: "scoreT.inflammation.1", defaultValue: "Add nuts, seeds or avocado · they lift this score even though they add fat.")),
            Rule(text: String(localized: "scoreT.inflammation.2", defaultValue: "Choose oily fish once or twice this week · salmon, sardines, mackerel."), objectives: ["strong_body", "resilience", "age_well"]),
            Rule(text: String(localized: "scoreT.inflammation.3", defaultValue: "Swap a cured or processed meat for fresh fish, meat or a legume."), maxAvg: 70),
            Rule(text: String(localized: "scoreT.inflammation.4", defaultValue: "Bake, roast or grill instead of deep-frying · the fat source changes, not just the amount."), maxAvg: 60),
            Rule(text: String(localized: "scoreT.inflammation.5", defaultValue: "Where a meal leans on cheese or cream, let a whole-food fat carry some of it."), trend: .down),
        ]
        case .digestion: [
            Rule(text: String(localized: "scoreT.digestion.0", defaultValue: "Add one more vegetable rather than more of the one already there.")),
            Rule(text: String(localized: "scoreT.digestion.1", defaultValue: "Add a legume · lentils, chickpeas or beans lift fibre and plant count together.")),
            Rule(text: String(localized: "scoreT.digestion.2", defaultValue: "Scatter nuts or seeds over what you already made · a small handful counts as a plant."), maxAvg: 70),
            Rule(text: String(localized: "scoreT.digestion.3", defaultValue: "Rotate which plants you use across the week rather than repeating the same three."), objectives: ["gut"]),
            Rule(text: String(localized: "scoreT.digestion.4", defaultValue: "Choose an intact grain · oats, barley, quinoa and whole-grain rice all count here."), objectives: ["sleep", "energy"]),
            Rule(text: String(localized: "scoreT.digestion.5", defaultValue: "Keep the skins on where you can · much of a vegetable's fibre sits just under them."), maxAvg: 60, trend: .down),
        ]
        }
    }

    /// Three goal/band/trend-matched tips: the specific ones first, then the evergreen ones, then the rest of
    /// the bank pads the list so the contract is always exactly three.
    static func tips(_ kind: MealScoreKind, objectives: [String], _ ctx: Context) -> [String] {
        let bank = bank(kind)
        let specific = bank.filter { $0.conditional && $0.matches(objectives, ctx) }
        let general = bank.filter { !$0.conditional }
        var out: [String] = []
        for r in specific + general + bank {
            if !out.contains(r.text) { out.append(r.text) }
            if out.count == 3 { break }
        }
        return out
    }
}
