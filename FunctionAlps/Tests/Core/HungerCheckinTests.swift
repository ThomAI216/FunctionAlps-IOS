import Foundation
import Testing
@testable import FunctionAlps

/// The evening hunger read: two raw 0–100 sliders and three stored-not-scored pill groups.
/// Recorded, NEVER scored — `between` has no better end, so it must never gain an overall or a ramp.
@Suite("Hunger check-in")
struct HungerCheckinTests {
    private let t0 = Date(timeIntervalSince1970: 1_788_350_400)

    @Test func hungerIsRecordedNeverScored() {
        var a = DimAnswers.empty
        a.sliders = ["between": 85, "satiety": 20]
        #expect(CheckinEngine.dimensionOverall(.hunger, a) == nil)
        #expect(FunctionalSchema.hunger.scored == false)
        // Only "how hungry" is neutral; fullness keeps the higher-is-better ramp.
        #expect(FunctionalSchema.hunger.sliders.map(\.key) == ["between", "satiety"])
        #expect(FunctionalSchema.hunger.sliders.map(\.neutral) == [true, false])
        #expect(FunctionalSchema.dimensions.filter { !$0.scored }.map(\.key) == [.hunger])
    }

    @Test func theServerPayloadCarriesTheRawHungerReads() {
        var a = FunctionalAnswers.blank
        a[.hunger]?.sliders = ["between": 82.4]
        #expect(CheckinEngine.answersJSON(a) == .object(["hunger": .object(["between": .number(82.4)])]))
        a[.hunger]?.sliders["satiety"] = 25
        #expect(CheckinEngine.answersJSON(a) == .object(["hunger": .object(["between": .number(82.4), "satiety": .number(25)])]))
    }

    @Test func aHungerOnlyEveningIsContentAndRoundTrips() {
        var a = FunctionalAnswers.blank
        a[.hunger]?.sliders = ["between": 72.6, "satiety": 30]
        a[.hunger]?.pills = ["cravings": ["sweet"], "hunger_drivers": ["stress", "boredom"], "hunger_when": ["evening"]]
        let m = CheckinEngine.momentFromAnswers(slot: .evening, answers: a, catalogPills: [:], note: nil, submittedAt: t0)
        #expect(m.hungerBetweenMeals == 73 && m.hungerSatiety == 30)
        #expect(m.energyOverall == nil && m.moodScore == nil) // hunger feeds no marker
        #expect(m.pills == ["cravings": ["sweet"], "hunger_drivers": ["stress", "boredom"], "hunger_when": ["evening"]])
        #expect(CheckinEngine.momentHasContent(m))
        #expect(CheckinEngine.momentEvents(m).isEmpty) // never an nb_checkin_events row

        let answers = CheckinEngine.answersFromMoment(m)
        #expect(answers[.hunger]?.sliders == ["between": 73, "satiety": 30])
        #expect(answers[.hunger]?.pills == ["cravings": ["sweet"], "hunger_drivers": ["stress", "boredom"], "hunger_when": ["evening"]])
        #expect(CheckinEngine.dimension(forGroup: "hunger_drivers") == .hunger)
        #expect(CheckinEngine.dimension(forGroup: "cravings") == .hunger)
    }

    @Test func theFollowUpsOpenOnlyWhenTheyMeanSomething() {
        let spec = FunctionalSchema.hunger
        func modules(_ sliders: [String: Double]) -> [String] {
            var a = DimAnswers.empty
            a.sliders = sliders
            return CheckinEngine.selectPills(spec, a).map(\.key)
        }
        #expect(modules([:]).isEmpty)
        #expect(modules(["between": 30, "satiety": 70]) == ["cravings"])
        // Hungry all day → what drove it, and when.
        #expect(modules(["between": 80]) == ["cravings", "hunger_drivers", "hunger_when"])
        // Never full → what drove it (no "when": the hunger itself was not high).
        #expect(modules(["between": 50, "satiety": 20]) == ["cravings", "hunger_drivers"])
    }

    @Test func pillGroupKeysDoNotCollideWithAnotherDimension() {
        let hungerGroups = Set(FunctionalSchema.hunger.pills.map(\.key))
        let others = FunctionalSchema.dimensions.filter { $0.key != .hunger }.flatMap { $0.pills.map(\.key) }
        #expect(hungerGroups.isDisjoint(with: others))
        #expect(hungerGroups.isDisjoint(with: PillCatalog.ownedGroups))
    }
}
