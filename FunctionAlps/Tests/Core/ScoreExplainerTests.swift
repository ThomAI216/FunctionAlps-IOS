import Foundation
import Testing
@testable import FunctionAlps

struct ScoreHistoryTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ back: Int, _ now: Date) -> Date { cal.date(byAdding: .day, value: -back, to: now)! }

    private func meal(_ at: Date, _ i: Int, _ g: Int, _ d: Int) -> MealLog {
        MealLog(id: UUID().uuidString, loggedAt: at, scores: MealScores(inflammation: i, glycemic: g, digestion: d))
    }

    @Test func daysAreBucketedLocallyAndAveraged() {
        let now = Date()
        let meals = [meal(now, 80, 60, 40), meal(now, 60, 60, 60), meal(day(1, now), 50, 50, 50), MealLog(id: "unscored", loggedAt: now)]
        let h = ScoreHistory.build(meals, days: 14, now: now, calendar: cal)
        #expect(h.count == 14)
        #expect(h.last?.inflammation == 70 && h.last?.glycemic == 60 && h.last?.digestion == 50)
        #expect(h[12].inflammation == 50)
        #expect(h[0].inflammation == nil)
    }

    @Test func recentAverageIgnoresEmptyDaysAndTrendNeedsBothHalves() {
        let now = Date()
        let recentOnly = ScoreHistory.build([meal(now, 90, 90, 90), meal(day(2, now), 70, 70, 70)], now: now, calendar: cal)
        #expect(ScoreHistory.recentAvg(recentOnly, .inflammation) == 80)
        #expect(ScoreHistory.trend(recentOnly, .inflammation) == nil)   // nothing in the prior half
        let both = ScoreHistory.build([meal(day(10, now), 50, 50, 50), meal(now, 70, 51, 40)], now: now, calendar: cal)
        #expect(ScoreHistory.trend(both, .inflammation) == .up)
        #expect(ScoreHistory.trend(both, .glycemic) == .flat)
        #expect(ScoreHistory.trend(both, .digestion) == .down)
        #expect(ScoreHistory.hasEnoughData(both, .inflammation) && !ScoreHistory.hasEnoughData(recentOnly, .glycemic, min: 3))
    }
}

struct ScorePersonalizationTests {
    @Test func whyFallsBackWhenNothingIsKnown() {
        #expect(ScorePersonalization.whyItMatters(.digestion, objectives: [], .init(avg: nil, trend: nil)) == nil)
        let known = ScorePersonalization.whyItMatters(.digestion, objectives: [], .init(avg: 72, trend: .up))
        #expect(known?.contains("72") == true)
        let goal = ScorePersonalization.whyItMatters(.digestion, objectives: ["gut"], .init(avg: nil, trend: nil))
        #expect(goal?.hasPrefix("Fibre and plant variety") == true)
    }

    @Test func tipsAreAlwaysThreeSpecificFirst() {
        let none = ScorePersonalization.tips(.glycemic, objectives: [], .init(avg: nil, trend: nil))
        #expect(none.count == 3 && Set(none).count == 3)
        let low = ScorePersonalization.tips(.glycemic, objectives: [], .init(avg: 50, trend: .down))
        #expect(low.count == 3)
        #expect(low[0].hasPrefix("Eat fruit whole") && low[1].hasPrefix("Replace a sweetened drink"))
        let goal = ScorePersonalization.tips(.inflammation, objectives: ["age_well"], .init(avg: nil, trend: nil))
        #expect(goal.first?.hasPrefix("Choose oily fish") == true)
    }
}

struct PatternTextTests {
    private func p(_ kind: String = "pattern", _ subject: String, _ reaction: String, tier: String = "confirmed", n: Int = 7, c: Double? = 0.8, dir: String = "worse") -> UserPattern {
        UserPattern(kind: kind, subject: subject, reaction: reaction, direction: dir, effect: -1, nObs: n, consistency: c, tier: tier)
    }

    @Test func sentencesComeFromTheRowOnly() {
        #expect(PatternText.sentence(p("pattern", "late_dinner", "next_sleep")) == "We've seen that when you eat dinner late, your sleep that night tends to suffer · seen 7 times (80% consistent).")
        #expect(PatternText.sentence(p("trigger_food", "onions", "bloating", tier: "hint", n: 3, c: nil)) == "Early signal · when onions is on your plate, bloating tends to follow · seen 3 times.")
        #expect(PatternText.sentence(p("pattern", "unknown_subject", "next_sleep")) == nil)
        #expect(PatternText.sentence(p("pattern", "late_dinner", "next_sleep", dir: "better")) == nil)
    }

    @Test func rankedAndFilteredPerScore() {
        let rows = [
            p("pattern", "late_dinner", "next_sleep", tier: "hint", n: 3, c: 0.9),
            p("pattern", "high_glycemic", "next_energy", tier: "confirmed", n: 11, c: 0.79),
            p("pattern", "high_fat_dinner", "bloating", tier: "confirmed", n: 6, c: 0.7),
            p("trigger_food", "onions", "bloating", tier: "hint", n: 4, c: 0.75),
        ]
        let glycemic = PatternText.forScore(rows, .glycemic)
        #expect(glycemic.map(\.subject) == ["high_glycemic", "late_dinner"])
        let digestion = PatternText.forScore(rows, .digestion)
        #expect(digestion.map(\.subject) == ["high_fat_dinner", "onions"])
        #expect(PatternText.forScore(rows, .inflammation).isEmpty)
    }
}
