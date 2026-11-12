import Foundation
import Testing
@testable import FunctionAlps

@Suite("Today's focus — the matrix cell, the card, the kickoff routine, the evening follow-up")
struct TodaysFocusTests {
    /// `member-daily-focus` on a low-battery morning (P5), as the function shapes it.
    private let p5 = """
    {"day":"2026-11-12","needsCheckin":false,
     "offers":[
       {"id":"o2","offerKey":"bank:hyd","cardId":"hyd","rank":2,"title":"A glass of water before coffee","description":"Start hydrated.","pillar":"nutrition","slot":"morning","variant":"standard","reason":"focus","trigger":"P5","stateTitle":null,"accepted":null,"completed":false},
       {"id":"o1","offerKey":"bank:rest","cardId":"rest","rank":1,"title":"10 minutes to wind down","description":null,"pillar":"sleep","slot":"evening","variant":"standard","reason":"focus","trigger":"P5","stateTitle":null,"accepted":true,"completed":true}
     ],
     "readiness":{"band":"low","vsBaseline":false,"source":"self_report"},
     "cell":{"id":"P5","headline":"Today is for holding steady","line":"Keep one priority, lighten the rest.","tone":"rest",
             "practitionerLine":"We'll look at it together with your practitioner.","hardMorning":true,
             "kickoff":{"key":"kickoff_morning","title":"Kickoff morning routine","subtitle":"Small steps for a slow morning.",
                        "finishTitle":"Your morning has started","finishLine":"Take the rest of the day at your own pace.",
                        "steps":[
                          {"kind":"movement","label":"Movement","cardId":"move","title":"Morning activation, five minutes","description":"Wake the body."},
                          {"kind":"breathing","label":"Breathing","cardId":"breath","title":"5 minutes of breathing","description":null},
                          {"kind":"light","label":"Daylight","cardId":"light","title":"Daylight first thing","description":null},
                          {"kind":"connection","label":"Connection & positivity","cardId":"connect","title":"Reach out","description":null},
                          {"kind":"hydration","label":"Hydration","cardId":"hyd","title":"A glass of water","description":null},
                          {"kind":"protein","label":"High-protein breakfast","cardId":"prot","title":"Protein at breakfast","description":null}]}}}
    """

    private func decode(_ json: String) throws -> TodayFocus { try JSON.decode(TodayFocus.self, from: Data(json.utf8)) }

    // MARK: Decoding

    @Test func decodesTheCellTheChipsAndTheKickoff() throws {
        let focus = try decode(p5)
        let cell = try #require(focus.cell)
        #expect(cell.id == "P5")
        #expect(cell.headline == "Today is for holding steady")
        #expect(cell.toneKind == .rest)
        #expect(cell.practitionerLine == "We'll look at it together with your practitioner.")
        #expect(cell.hardMorning)
        let kickoff = try #require(cell.kickoff)
        #expect(kickoff.title == "Kickoff morning routine")
        #expect(kickoff.finishTitle == "Your morning has started")
        #expect(kickoff.steps.count == 6)
        #expect(focus.offers.first?.bankCardId == "hyd")
        #expect(focus.offers.first?.completed == false)
    }

    @Test func aReplyFromBeforeTheMatrixStillDecodes() throws {
        let old = #"{"day":"2026-11-12","needsCheckin":false,"offers":[{"id":"o1","offerKey":"state:stressed:x","rank":1,"title":"Three slow breaths","description":null,"pillar":null,"slot":null,"variant":"easy","reason":"state","trigger":"stressed","stateTitle":"A two-minute reset","accepted":null,"completed":false}]}"#
        let focus = try decode(old)
        #expect(focus.cell == nil)
        #expect(focus.offers.first?.bankCardId == nil)   // a state offer opens no card
        let lead = try #require(focus.offers.first)
        #expect(FocusCardLogic.state(focus) == .offersOnly(lead: lead, also: []))
    }

    @Test func anUnknownToneIsSteadyAndAMissingPractitionerLineIsNil() throws {
        let json = #"{"day":"d","needsCheckin":false,"offers":[],"cell":{"id":"O1","headline":"h","line":"l","tone":"purple","practitionerLine":null,"hardMorning":false,"kickoff":null}}"#
        let cell = try #require(try decode(json).cell)
        #expect(cell.toneKind == .soft)
        #expect(cell.practitionerLine == nil)
        #expect(cell.kickoff == nil)
    }

    @Test func aTickKeepsTheCell() throws {
        let focus = try decode(p5)
        let ticked = focus.replacing(offers: focus.offers.map { var o = $0; o.completed = true; return o })
        #expect(ticked.cell == focus.cell)
        #expect(ticked.offers.allSatisfy(\.completed))
        #expect(ticked.readiness == focus.readiness)
    }

    // MARK: The card's states

    @Test func theCardStates() throws {
        // no morning yet: the card is the way in
        let none = try decode(#"{"day":"d","needsCheckin":true,"offers":[],"cell":null}"#)
        #expect(FocusCardLogic.state(none) == .needsCheckin)
        // a cell: its habits ride as chips, in rank order, three at most
        guard case .cell(let cell, let chips) = FocusCardLogic.state(try decode(p5)) else { Issue.record("expected a cell"); return }
        #expect(cell.id == "P5")
        #expect(chips.map(\.id) == ["o1", "o2"])
        // nothing to say
        let empty = try decode(#"{"day":"d","needsCheckin":false,"offers":[]}"#)
        #expect(FocusCardLogic.state(empty) == .nothing)
    }

    @Test func atMostThreeChipsAndOnlyOnesThatOpenACard() throws {
        func offer(_ id: Int, key: String) -> String {
            #"{"id":"o\#(id)","offerKey":"\#(key)","rank":\#(id),"title":"t\#(id)","description":null,"pillar":null,"slot":null,"variant":null,"reason":"focus","trigger":"P2","stateTitle":null,"accepted":null,"completed":false}"#
        }
        let json = #"{"day":"d","needsCheckin":false,"offers":["# + [offer(1, key: "bank:a"), offer(2, key: "state:x:y"), offer(3, key: "bank:c"), offer(4, key: "bank:d"), offer(5, key: "bank:e")].joined(separator: ",") + "]}"
        let chips = FocusCardLogic.chips(try decode(json).offers)
        #expect(chips.map(\.id) == ["o1", "o3", "o4"])
    }

    @Test func theKickoffButtonNeedsARoutineWithSomethingToWalk() throws {
        let cell = try #require(try decode(p5).cell)
        #expect(FocusCardLogic.kickoff(cell)?.steps.count == 6)
        let single = #"{"day":"d","needsCheckin":false,"offers":[],"cell":{"id":"P5","headline":"h","line":"l","tone":"rest","practitionerLine":null,"hardMorning":true,"kickoff":{"key":"k","title":"t","subtitle":"s","steps":[{"kind":"movement","label":"Movement","cardId":"a","title":"A","description":null}]}}}"#
        let thin = try #require(try decode(single).cell)
        #expect(FocusCardLogic.kickoff(thin) == nil)
    }

    // MARK: The kickoff routine

    @Test func theRoutineKeepsTheServersOrderAndWalksOneStepAtATime() throws {
        let kickoff = try #require(try decode(p5).cell?.kickoff)
        #expect(kickoff.steps.map(\.kind) == ["movement", "breathing", "light", "connection", "hydration", "protein"])
        var progress = KickoffProgress(total: kickoff.steps.count)
        #expect(progress.stepNumber == 1)
        #expect(!progress.canGoBack)
        progress.tick()
        #expect(progress.stepNumber == 2)
        #expect(progress.canGoBack)
        progress.back()
        #expect(progress.stepNumber == 1)
        progress.back()                                // never before the first step
        #expect(progress.stepNumber == 1)
        for _ in 0..<5 { progress.tick() }
        #expect(progress.stepNumber == 6)              // the last step, not yet finished
        #expect(!progress.isFinished)
        progress.tick()                                // the tick on the last step opens the finish screen
        #expect(progress.isFinished)
        #expect(progress.stepNumber == 6)
        progress.tick()                                // and goes no further
        #expect(progress.isFinished)
        progress.back()
        #expect(!progress.isFinished)
    }

    @Test func anEmptyRoutineIsFinishedAtOnce() {
        #expect(KickoffProgress(total: 0).isFinished)
    }

    // MARK: The evening follow-up

    @Test func itIsAskedOnlyInTheDailyCheckInAfterAHardMorning() throws {
        let hard = try #require(try decode(p5).cell)
        let easy = try #require(try decode(#"{"day":"d","needsCheckin":false,"offers":[],"cell":{"id":"G1","headline":"h","line":"l","tone":"peak","practitionerLine":null,"hardMorning":false,"kickoff":null}}"#).cell)
        #expect(EveningFollowupLogic.isAsked(cell: hard, slot: .evening, catchingUp: false))
        #expect(!EveningFollowupLogic.isAsked(cell: hard, slot: .morning, catchingUp: false))
        #expect(!EveningFollowupLogic.isAsked(cell: hard, slot: .evening, catchingUp: true))
        #expect(!EveningFollowupLogic.isAsked(cell: easy, slot: .evening, catchingUp: false))
        #expect(!EveningFollowupLogic.isAsked(cell: nil, slot: .evening, catchingUp: false))
    }

    @Test func thePillsAreWhatWasDoneTodayThenTheGenericOnes() throws {
        let habit = HabitRow(id: "h1", carePlanItemId: nil, title: "Morning circadian routine", description: nil, frequencyRule: nil, status: "active",
                             source: "prescribed", pillar: nil, slot: "morning", appearsAfterHabitId: nil, easyTitle: nil, easyDescription: nil,
                             revTitle: nil, revDescription: nil, createdAt: "2026-10-01T08:00:00Z", habitBankId: "card-1")
        let other = HabitRow(id: "h2", carePlanItemId: nil, title: "Evening walk", description: nil, frequencyRule: nil, status: "active",
                             source: "prescribed", pillar: nil, slot: "evening", appearsAfterHabitId: nil, easyTitle: nil, easyDescription: nil,
                             revTitle: nil, revDescription: nil, createdAt: "2026-10-01T08:00:00Z")
        let plan = HabitPlan(day: "2026-11-12", header: nil, phases: [], habits: [habit, other],
                             completions: [HabitCompletionRow(id: "c1", habitId: "h1", completionDate: "2026-11-12"),
                                           HabitCompletionRow(id: "c0", habitId: "h2", completionDate: "2026-11-11")])
        let focus = try decode(p5)
        let options = EveningFollowupLogic.options(plan: plan, offers: focus.offers, saved: [])
        // the plan habit done today, the focus offer ticked as done, then the six generic answers; yesterday's completion is not listed
        #expect(options.map(\.key) == ["habit:card-1", "habit:rest"] + EveningFollowupLogic.genericKeys)
        #expect(options.first?.label == "Morning circadian routine")
        #expect(!options.contains { $0.label == "Evening walk" })
    }

    @Test func aTitleDoneTwiceIsListedOnce() throws {
        let focus = try decode(p5)
        let doubled = focus.offers + focus.offers
        #expect(EveningFollowupLogic.completedToday(plan: nil, offers: doubled).count == 1)
    }

    @Test func pillsToggle() {
        #expect(EveningFollowupLogic.toggled([], "rest") == ["rest"])
        #expect(EveningFollowupLogic.toggled(["rest", "food"], "rest") == ["food"])
    }

    @Test func thePayloadWritesOnlyTheFollowupColumnsAndTheRowKey() throws {
        let followup = EveningFollowup(choice: .harder, pills: ["people", "habit:card-1"])
        let patch = EveningFollowupLogic.columns(followup, patientId: "p-1", day: "2026-11-12")
        #expect(Set(patch.keys) == ["patient_id", "day", "evening_followup", "evening_pills"])   // never the morning's mood / energy / pills
        let data = try JSONEncoder().encode(patch)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["evening_followup"] as? Int == -1)
        #expect(object["evening_pills"] as? [String] == ["people", "habit:card-1"])
        #expect(object["patient_id"] as? String == "p-1")
        #expect(object["day"] as? String == "2026-11-12")
    }

    @Test func theThreeAnswersMapToMinusOneZeroOne() {
        #expect(EveningFollowup.Choice.harder.rawValue == -1)
        #expect(EveningFollowup.Choice.same.rawValue == 0)
        #expect(EveningFollowup.Choice.better.rawValue == 1)
        #expect(EveningFollowup.Choice(rawValue: 1) == .better)
        #expect(EveningFollowup.Choice(rawValue: 2) == nil)
    }

    @Test func noAnswerWritesNull() throws {
        let patch = EveningFollowupLogic.columns(EveningFollowup(choice: nil, pills: ["rest"]), patientId: "p", day: "d")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
        #expect(object["evening_followup"] is NSNull)
        #expect(EveningFollowup().isEmpty)
    }
}
