import Foundation
import Testing
@testable import FunctionAlps

/// Ports of the Expo app's functional-engine / moments rules — a moment saved from the phone
/// must score exactly as one saved from the web.
@Suite("CheckinEngine")
struct CheckinEngineTests {
    private let t0 = Date(timeIntervalSince1970: 1_788_350_400)

    @Test func energyIsMeanModulatedByStability() {
        #expect(CheckinEngine.energyOverall(body: 60, mind: 80, stability: nil) == 70)
        #expect(CheckinEngine.energyOverall(body: 60, mind: 80, stability: 100) == 81)
        #expect(CheckinEngine.energyOverall(body: 60, mind: 80, stability: 0) == 60)
        #expect(CheckinEngine.energyOverall(body: nil, mind: nil, stability: 50) == nil)
        #expect(CheckinEngine.energyOverall(body: 100, mind: 100, stability: 100) == 100)
        #expect(CheckinEngine.energyOverall(body: 70, mind: nil, stability: nil) == 70)
    }

    @Test func sleepScores() {
        #expect(CheckinEngine.durationScore(480) == 100)
        #expect(CheckinEngine.durationScore(360) == 80)
        #expect(CheckinEngine.durationScore(600) == 90)
        #expect(CheckinEngine.durationScore(0) == 0)
        #expect(CheckinEngine.durationScore(nil) == nil)
        #expect(CheckinEngine.sleepOverall(durationMin: 480, latency: "15_30", wakeCount: "1_2", refreshed: 70) == 81)
        #expect(CheckinEngine.sleepOverall(durationMin: nil, latency: nil, wakeCount: nil, refreshed: 70) == 70)
        #expect(CheckinEngine.sleepOverall(durationMin: nil, latency: "gt_60", wakeCount: nil, refreshed: nil) == 20)
        #expect(CheckinEngine.sleepOverall(durationMin: nil, latency: nil, wakeCount: nil, refreshed: nil) == nil)
    }

    @Test func legacyMountainScale() {
        #expect(CheckinEngine.toLegacy(0) == 1)
        #expect(CheckinEngine.toLegacy(10) == 1)
        #expect(CheckinEngine.toLegacy(30) == 2)
        #expect(CheckinEngine.toLegacy(50) == 3)
        #expect(CheckinEngine.toLegacy(100) == 5)
        #expect(CheckinEngine.toLegacy(nil) == nil)
    }

    @Test func bandsAndSlots() {
        #expect(FunctionalSchema.bandLevel(39) == .low)
        #expect(FunctionalSchema.bandLevel(40) == .mid)
        #expect(FunctionalSchema.bandLevel(60) == .mid)
        #expect(FunctionalSchema.bandLevel(61) == .high)
        #expect(FunctionalSchema.bandLevel(nil) == nil)
        #expect(MomentSlot.current(hour: 0) == .morning)
        #expect(MomentSlot.current(hour: 10) == .morning)
        #expect(MomentSlot.current(hour: 11) == .midday)
        #expect(MomentSlot.current(hour: 16) == .midday)
        #expect(MomentSlot.current(hour: 17) == .evening)
        #expect(MomentSlot.current(hour: 23) == .evening)
    }

    @Test func precisionPillsFollowTheBands() {
        var a = DimAnswers.empty
        a.sliders = ["body": 30, "mind": 80]
        let keys = CheckinEngine.selectPills(FunctionalSchema.energy, a).map(\.key)
        #expect(keys.contains("drained"))
        #expect(keys.contains("fuelled"))
        #expect(!keys.contains("best_moment"))
        a.sliders["stability"] = 50
        #expect(CheckinEngine.selectPills(FunctionalSchema.energy, a).map(\.key).contains("best_moment"))
        var s = DimAnswers.empty
        s.specials.latency = "gt_60"
        #expect(CheckinEngine.selectPills(FunctionalSchema.sleep, s).map(\.key) == ["kept_up"])
    }

    @Test func momentFromAnswersKeepsCalmnessAndMergesCatalogPills() {
        var answers = FunctionalAnswers.blank
        answers[.energy]?.sliders = ["body": 60, "mind": 80]
        answers[.energy]?.pills = ["fuelled": ["movement"], "best_moment": ["morning"]]
        answers[.stress]?.sliders = ["calm": 58]
        answers[.sleep]?.sliders = ["refreshed": 40]
        answers[.sleep]?.specials = SleepSpecials(bedTime: "22:00", wakeTime: "06:00", durationMin: 480, latency: "lt_15", wakeCount: "0")
        let m = CheckinEngine.momentFromAnswers(slot: .morning, answers: answers, catalogPills: ["day_intent": ["intent_calm"], "fuelled": []], note: "  ", submittedAt: t0)
        #expect(m.energyOverall == 70)
        #expect(m.stressScore == 58)
        #expect(m.moodScore == nil)
        #expect(m.sleepRefreshed == 40)
        #expect(m.sleepDurationMin == 480)
        #expect(m.sleepOverall == 79) // 40*.35 + 100*.3 + 100*.2 + 100*.15 = 79
        #expect(m.pills == ["best_moment": ["morning"], "day_intent": ["intent_calm"]]) // energy's own "fuelled" is catalog-owned
        #expect(m.note == nil)
    }

    @Test func emptyMomentHasNoContent() {
        let empty = CheckinEngine.momentFromAnswers(slot: .midday, answers: .blank, catalogPills: [:], note: nil, submittedAt: t0)
        #expect(!CheckinEngine.momentHasContent(empty))
        var pillOnly = empty
        pillOnly.pills = ["drained": ["travel"]]
        #expect(CheckinEngine.momentHasContent(pillOnly))
        var noteOnly = empty
        noteOnly.note = "tired"
        #expect(CheckinEngine.momentHasContent(noteOnly))
    }

    @Test func answersRoundTripThroughAMoment() {
        let saved = CheckinMoment(slot: .morning, submittedAt: t0, energyBody: 60, energyMind: 80, energyStability: 50, energyOverall: 70, moodScore: 65, stressScore: 58,
                                  sleepOverall: 79, sleepRefreshed: 40, sleepDurationMin: 480, sleepLatencyBand: "lt_15", sleepWakeCount: "0",
                                  pills: ["kept_up": ["noise"], "day_intent": ["intent_calm"], "fuelled": ["music"]], note: nil)
        let answers = CheckinEngine.answersFromMoment(saved)
        #expect(answers[.energy]?.sliders == ["body": 60, "mind": 80, "stability": 50])
        #expect(answers[.mood]?.sliders == ["mood": 65])
        #expect(answers[.stress]?.sliders == ["calm": 58])
        #expect(answers[.sleep]?.sliders == ["refreshed": 40])
        #expect(answers[.sleep]?.specials.latency == "lt_15")
        #expect(answers[.sleep]?.pills == ["kept_up": ["noise"]])
        #expect(answers[.energy]?.pills.isEmpty == true) // catalog groups stay out of the dimensions
        #expect(CheckinEngine.catalogPills(from: saved) == ["day_intent": ["intent_calm"], "fuelled": ["music"]])
        #expect(CheckinEngine.hasMoreTierAnswers(saved))
        let rebuilt = CheckinEngine.momentFromAnswers(slot: .morning, answers: answers, catalogPills: CheckinEngine.catalogPills(from: saved), note: nil, submittedAt: t0)
        #expect(rebuilt == saved)
    }

    private func moment(_ slot: MomentSlot, energy: Int? = nil, mood: Int? = nil, sleep: Int? = nil, stability: Int? = nil) -> CheckinMoment {
        CheckinMoment(slot: slot, submittedAt: t0, energyStability: stability, energyOverall: energy, moodScore: mood, sleepOverall: sleep)
    }

    @Test func daySummaryIsAMedianAndSleepComesFromTheMorning() {
        let s = CheckinEngine.summarizeDay([moment(.evening, energy: 100, sleep: 30), moment(.morning, energy: 40, sleep: 80), moment(.midday, energy: 70)])
        #expect(s.energyOverall == 70)
        #expect(s.sleepOverall == 80)
        #expect(s.momentCount == 3)
        let two = CheckinEngine.summarizeDay([moment(.morning, energy: 40), moment(.midday, energy: 70)])
        #expect(two.energyOverall == 55)
        // A morning without sleep still keeps a later moment from speaking for the night.
        #expect(CheckinEngine.summarizeDay([moment(.morning), moment(.evening, sleep: 30)]).sleepOverall == nil)
        // No morning at all → the earliest moment that carries sleep.
        #expect(CheckinEngine.summarizeDay([moment(.evening, sleep: 30), moment(.midday, sleep: 55)]).sleepOverall == 55)
        #expect(CheckinEngine.summarizeDay([]).momentCount == 0)
    }

    @Test func daySummaryPatchNeverWipes() {
        let existing = DailyCheckinCarry(recovery: 7, soreness: 3, energyBody: 33, sleepOverall: 88, energy: 2, sleep: 5)
        let patch = CheckinEngine.daySummaryPatch([moment(.midday, energy: 70, mood: 50, stability: 60)], existing: existing, completedAt: t0)
        #expect(patch.energyOverall == 70)
        #expect(patch.energyBody == 33)          // computed null → existing kept
        #expect(patch.energyStability == 60)
        #expect(patch.legacyEnergy == 4)         // 70/20 = 3.5 → 4
        #expect(patch.legacyMood == 3)
        #expect(patch.recovery == 7)             // felt prefill
        #expect(patch.soreness == 3)
        #expect(patch.sleep == nil)              // no sleep answer today → sleep columns omitted
        #expect(patch.completedAt == t0)

        let withSleep = CheckinEngine.daySummaryPatch([moment(.morning, sleep: 79)], existing: existing, completedAt: t0)
        #expect(withSleep.sleep?.sleepOverall == 79)
        #expect(withSleep.sleep?.legacySleep == 4)
        #expect(withSleep.energyOverall == nil)
        #expect(withSleep.energyBody == 33)
    }

    @Test func eventsOnlyForAnsweredMarkers() {
        let m = CheckinMoment(slot: .midday, submittedAt: t0, energyOverall: 70, stressScore: 58)
        let events = CheckinEngine.momentEvents(m)
        #expect(events.map(\.dimension) == ["energy", "stress"])
        #expect(events.map(\.value) == [70, 58])
        #expect(events.allSatisfy { $0.ts == t0 })
    }

    @Test func dayReadsInSlotOrder() {
        let reads = CheckinEngine.momentReads([moment(.evening), moment(.morning, energy: 72, mood: 60)])
        #expect(reads.map(\.slot) == [.morning, .evening])
        #expect(reads[0].summary == "E 72 · M 60")
        #expect(reads[1].summary == "Checked in")
        #expect(CheckinEngine.slotIsDone(reads.isEmpty ? [] : [moment(.morning)], .morning))
        #expect(!CheckinEngine.slotIsDone([moment(.morning)], .midday))
    }

    @Test func stateRampIndexRunsGreenToRed() {
        #expect(CheckinEngine.stateRampIndex(100) == 0)
        #expect(CheckinEngine.stateRampIndex(0) == 4)
        #expect(CheckinEngine.stateRampIndex(50) == 2)
    }
}
