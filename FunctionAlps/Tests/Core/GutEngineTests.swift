import Foundation
import Testing
@testable import FunctionAlps

@Suite("Gut engine — the form reads and the dashboard score")
struct GutEngineTests {
    @Test("Bristol and frequency scores follow gut-engine.ts")
    func stoolPieces() {
        #expect(GutEngine.bristolScore(3) == 100)
        #expect(GutEngine.bristolScore(4) == 100)
        #expect(GutEngine.bristolScore(2) == 50)
        #expect(GutEngine.bristolScore(1) == 0)
        #expect(GutEngine.bristolScore(5) == 67)
        #expect(GutEngine.bristolScore(6) == 33)
        #expect(GutEngine.bristolScore(7) == 0)
        #expect(GutEngine.bristolScore(nil) == nil)
        #expect(GutEngine.freqScore(2) == 100)
        #expect(GutEngine.freqScore(0) == 40)
        #expect(GutEngine.freqScore(5) == 70)
        #expect(GutEngine.freqScore(6) == 0)
    }

    @Test("Dimension reads: comfort is the slider, stool the mean of its three pieces, reactions prefers the meal score")
    func dimensionReads() {
        var a = GutAnswerSet.blank
        a[.comfort]?.sliders["comfort"] = 72
        a[.stool]?.specials.bristol = 4
        a[.stool]?.specials.frequency = 2
        a[.stool]?.sliders["ease"] = 70
        a[.reactions]?.sliders["reactions"] = 55
        #expect(GutEngine.dimensionOverall(.comfort, a[.comfort]!) == 72)
        #expect(GutEngine.dimensionOverall(.stool, a[.stool]!) == 90)      // (100 + 100 + 70) / 3
        #expect(GutEngine.dimensionOverall(.reactions, a[.reactions]!) == 55)
        a[.reactions]?.specials.reactionsScore = 64
        #expect(GutEngine.dimensionOverall(.reactions, a[.reactions]!) == 64)
        #expect(GutEngine.overall(a) == 75)                                 // (72 + 90 + 64) / 3 = 75.33
        #expect(GutEngine.to15(90) == 5)
        #expect(GutEngine.to15(5) == 1)
        #expect(GutEngine.events(a, at: Date()).map(\.dimension) == ["comfort", "stool", "reactions"])
        #expect(GutEngine.hasAnyAnswer(.blank) == false)
    }

    @Test("Pill modules appear only when the read is ≤ 60, and nested ones only after a pick")
    func branching() {
        var a = GutAnswers()
        #expect(GutSchema.visiblePills(GutSchema.comfort, a).isEmpty)
        a.sliders["comfort"] = 61
        #expect(GutSchema.visiblePills(GutSchema.comfort, a).isEmpty)
        a.sliders["comfort"] = 60
        #expect(GutSchema.visiblePills(GutSchema.comfort, a).map(\.key) == ["symptoms"])
        a.pills["symptoms"] = ["gas"]
        #expect(GutSchema.visiblePills(GutSchema.comfort, a).map(\.key) == ["symptoms", "timing", "trigger"])
    }

    @Test("Dashboard score is an available-case weighted mean (0.4 / 0.3 / 0.3)")
    func weighted() {
        let full = GutEngine.gutScore(comfort: 80, reactions: 60, stool: 40)
        #expect(full.score == 62)                                          // 32 + 18 + 12
        let partial = GutEngine.gutScore(comfort: 80, reactions: nil, stool: 40)
        #expect(partial.score == 63)                                       // (32 + 12) / 0.7 = 62.86
        #expect(GutEngine.gutScore(comfort: nil, reactions: nil, stool: nil).score == nil)
        #expect(full.factors.map(\.status) == ["good", "watch", "watch"])
    }

    @Test("Meal reactions: overall × 10 minus three times the mean symptom burden, averaged")
    func mealScore() {
        let a = MealReaction(overall: 8, flags: [], bloating: 2, fullness: 4, gas: 0)   // 80 − 6 = 74
        let b = MealReaction(overall: 5, flags: [])                                     // 50
        #expect(GutEngine.mealReactionsScore([a, b]) == 62)
        #expect(GutEngine.mealReactionsScore([MealReaction(overall: nil, flags: [])]) == nil)
    }

    @Test("Stool falls back to the legacy markers; comfort never does; reach-back takes the latest non-null per field")
    func signalsAndReachBack() {
        let old = GutDay(day: "2026-09-01", comfort: 70, stool: nil, reactions: nil, overall: nil, stoolQuality: 5, stoolFrequency: 2, completedAt: nil)
        let newer = GutDay(day: "2026-09-03", comfort: nil, stool: 55, reactions: nil, overall: nil, stoolQuality: nil, stoolFrequency: nil, completedAt: nil)
        let s = GutEngine.signals(entry: old, reactions: [])
        #expect(s.stool == 100)                                            // quality 5 → 100, frequency 2 → 100
        #expect(s.comfort == 70)
        #expect(s.reactions == nil)
        let latest = GutEngine.latestEntry(today: nil, history: [old, newer])
        #expect(latest?.comfort == 70)
        #expect(latest?.stool == 55)
        #expect(latest?.day == "2026-09-03")
        #expect(GutEngine.status(75) == .onTrack)
        #expect(GutEngine.status(55) == .needsSupport)
        #expect(GutEngine.status(54) == .watchClosely)
    }

    @Test("gut_detail round-trips with its mixed-case keys intact")
    func detailCodec() throws {
        var a = GutAnswerSet.blank
        a[.stool]?.pills["stool_off"] = ["incomplete"]
        a[.stool]?.specials.bristol = 4
        a[.reactions]?.specials.reactionsScore = 64
        a[.comfort]?.sliders["comfort"] = 72
        let encoded = GutDetailCodec.encode(answers: a, notes: " Late dinner. ")
        let data = try JSONEncoder().encode(encoded)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"reactionsScore\":64"))
        #expect(text.contains("\"stool_off\":[\"incomplete\"]"))
        let back = GutDetailCodec.decode(try JSONSerialization.jsonObject(with: data))
        #expect(back?.answers == a)
        #expect(back?.notes == "Late dinner.")
    }

    @Test("Felt summary follows the Expo rules")
    func felt() {
        #expect(GutDimensionCard.feltSummary(MealReaction(overall: 8, flags: [], bloating: 1, fullness: 2, gas: 0)) == "sat well")
        #expect(GutDimensionCard.feltSummary(MealReaction(overall: 4, flags: [], bloating: 8, fullness: 2, gas: 0)) == "felt bloated")
        #expect(GutDimensionCard.feltSummary(MealReaction(overall: 6, flags: [], bloating: 5, fullness: 2, gas: 0)) == "some bloating")
        #expect(GutDimensionCard.feltSummary(MealReaction(overall: 3, flags: [])) == "mixed reaction")
    }
}
