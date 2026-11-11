import Foundation
import Testing
@testable import FunctionAlps

/// The colour a meal reaction pill gets on Trends (owner request, 2026-11-11): by meaning, from the stored key.
@Suite("Reaction tone — green sat well, orange a bit off, red discomfort, grey unknown")
struct ReactionToneTests {
    @Test("Good words are positive")
    func positive() {
        for key in ["sat well", "felt good", "light", "energised", "Sat Well"] { #expect(ReactionTone.tone(for: key) == .positive) }
    }

    @Test("Mild words are orange, including stored snake_case keys")
    func mild() {
        for key in ["a bit off", "a bit bloated", "felt_full", "heavy", "tired after", "some bloating"] {
            #expect(ReactionTone.tone(for: key) == .mild, "\(key)")
        }
    }

    @Test("Strong discomfort is red")
    func strong() {
        for key in ["bloated", "bloating", "gas", "cramps", "cramping", "pain", "reflux", "nausea", "loose"] {
            #expect(ReactionTone.tone(for: key) == .strong, "\(key)")
        }
    }

    @Test("Unknown or empty stays grey")
    func neutral() {
        #expect(ReactionTone.tone(for: "") == .neutral)
        #expect(ReactionTone.tone(for: "after_walk") == .neutral)
    }

    @Test("The meal's rating maps to a tone")
    func sentiment() {
        #expect(ReactionTone.tone(for: .good) == .positive)
        #expect(ReactionTone.tone(for: .watch) == .mild)
        #expect(ReactionTone.tone(for: .bad) == .strong)
    }

    @Test("Food words carry one tone each, from the stored flag")
    func foodItems() {
        let items = TrendsEngine.reactionItems(MealReaction(overall: 5, flags: ["bloating", "heavy", "overall_off"], bloating: 6))
        #expect(items.map(\.tone) == [.mild, .strong, .mild])
        #expect(items.map(\.word).dropFirst() == ["bloating", "heavy"])
        #expect(TrendsEngine.reactionItems(nil).isEmpty)
    }
}
