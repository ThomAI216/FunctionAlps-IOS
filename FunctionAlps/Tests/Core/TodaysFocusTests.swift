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
       {"id":"o1","offerKey":"bank:rest","cardId":"rest","rank":1,"title":"A real pause at lunch","description":null,"pillar":"recovery","slot":"midday","variant":"standard","reason":"focus","trigger":"P5","stateTitle":null,"accepted":true,"completed":true}
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
        let allDone = ticked.offers.allSatisfy { $0.completed }
        #expect(allDone)
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

    @Test func thePillsAreEverythingProposedThenWhatWasDoneThenTheGenericOnes() throws {
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
        let options = EveningFollowupLogic.options(plan: plan, focus: focus, saved: [])
        // the kickoff routine and every habit the morning proposed (rank order), then the plan habit done today that is not among them,
        // then the six generic answers; yesterday's completion is not listed
        #expect(options.map(\.key) == ["kickoff", "habit:rest", "habit:hyd", "habit:card-1"] + EveningFollowupLogic.genericKeys)
        #expect(options.first?.label == "Kickoff morning routine")
        #expect(options.contains { $0.label == "Morning circadian routine" })
        #expect(!options.contains { $0.label == "Evening walk" })
    }

    @Test func aTitleDoneTwiceIsListedOnce() throws {
        let focus = try decode(p5)
        let doubled = focus.offers + focus.offers
        #expect(EveningFollowupLogic.completedToday(plan: nil, offers: doubled).count == 1)
    }

    @Test func proposedHabitsAreListedWhetherOrNotTheyWereDone() throws {
        let focus = try decode(p5)
        // rest was ticked, hyd was not: both are proposals, in rank order, after the kickoff pill
        let options = EveningFollowupLogic.options(plan: nil, focus: focus, saved: [])
        #expect(options.map(\.label).prefix(3) == ["Kickoff morning routine", "A real pause at lunch", "A glass of water before coffee"])
        #expect(Array(options.map(\.key).suffix(6)) == EveningFollowupLogic.genericKeys)
    }

    @Test func noKickoffPillWhenTheMorningDidNotOfferTheRoutine() throws {
        let json = #"{"day":"d","needsCheckin":false,"offers":[],"cell":{"id":"O1","headline":"h","line":"l","tone":"soft","practitionerLine":null,"hardMorning":true,"kickoff":null}}"#
        let options = EveningFollowupLogic.options(plan: nil, focus: try decode(json), saved: [])
        #expect(options.map(\.key) == EveningFollowupLogic.genericKeys)
        #expect(EveningFollowupLogic.options(plan: nil, focus: nil, saved: []).map(\.key) == EveningFollowupLogic.genericKeys)
    }

    @Test func pillsAreDedupedByKeyAndByTitleAndASavedKeyStays() throws {
        let focus = try decode(p5)
        // the same card twice, and an offer titled like a generic answer ("Movement"): each is listed once
        let twice = focus.replacing(offers: focus.offers + focus.offers + [
            try JSON.decode(FocusOffer.self, from: Data(#"{"id":"o9","offerKey":"bank:mv","cardId":"mv","rank":9,"title":"Movement","description":null,"pillar":null,"slot":null,"variant":null,"reason":"focus","trigger":"P5","stateTitle":null,"accepted":null,"completed":true}"#.utf8))])
        let options = EveningFollowupLogic.options(plan: nil, focus: twice, saved: ["habit:gone", "kickoff"])
        let keys = options.map(\.key)
        #expect(Set(keys).count == keys.count)
        let titles = options.map { $0.label.lowercased() }
        #expect(Set(titles).count == titles.count)
        #expect(keys.contains("habit:gone"))   // saved earlier, since undone: still offered
        #expect(keys.first == "habit:gone")
        #expect(keys.filter { $0 == "kickoff" }.count == 1)
    }

    // MARK: The green row on Home

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func moment(_ hour: Int, _ minute: Int, day: Int = 13) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func theKickoffRowAppearsOnlyOnHardMorningCellsOnceTheCheckinIsDone() throws {
        let hard = try decode(p5)
        let easy = try decode(#"{"day":"2026-11-12","needsCheckin":false,"offers":[],"cell":{"id":"G1","headline":"h","line":"l","tone":"peak","practitionerLine":null,"hardMorning":false,"kickoff":null}}"#)
        let noRoutine = try decode(#"{"day":"2026-11-12","needsCheckin":false,"offers":[],"cell":{"id":"P2","headline":"h","line":"l","tone":"soft","practitionerLine":null,"hardMorning":true,"kickoff":null}}"#)
        func row(_ focus: TodayFocus?, _ slot: HabitSlot, done: Bool = true) -> KickoffRow? {
            KickoffRowLogic.row(focus: focus, slot: slot, morningCheckinDone: done, run: nil, wakeTime: "06:45", calendar: utc)
        }
        let shown = try #require(row(hard, .midday))
        #expect(shown.subtitle == "Today is for holding steady")
        #expect(!shown.done)
        #expect(row(hard, .morning) != nil)
        #expect(row(hard, .midday, done: false) == nil)   // check-in not done
        #expect(row(hard, .evening) == nil)
        #expect(row(easy, .midday) == nil)
        #expect(row(noRoutine, .midday) == nil)
        #expect(row(nil, .midday) == nil)
    }

    // MARK: The deadline (owner, 2026-11-13)

    @Test func theDeadlineIsAnHourAfterWakingElseTen() {
        #expect(KickoffDeadline.dueAt(day: "2026-11-13", wakeTime: "06:45", calendar: utc) == moment(7, 45))
        #expect(KickoffDeadline.dueAt(day: "2026-11-13", wakeTime: "07:30:00", calendar: utc) == moment(8, 30))   // a postgres time
        #expect(KickoffDeadline.dueAt(day: "2026-11-13", wakeTime: "23:30", calendar: utc) == moment(0, 30, day: 14))   // wraps, never crashes
        #expect(KickoffDeadline.dueAt(day: "2026-11-13", wakeTime: nil, calendar: utc) == moment(10, 0))
        #expect(KickoffDeadline.dueAt(day: "2026-11-13", wakeTime: "soon", calendar: utc) == moment(10, 0))
        #expect(KickoffDeadline.dueAt(day: "not a day", wakeTime: "06:45", calendar: utc) == nil)
        #expect(KickoffDeadline.clock(moment(7, 45), calendar: utc) == "07:45")
    }

    @Test func theRowCarriesTheDeadlineFromTheWakeTimeOrTheRunsOwn() throws {
        let hard = try decode(#"{"day":"2026-11-13","needsCheckin":false,"offers":[],"cell":{"id":"P5","headline":"h","line":"l","tone":"rest","practitionerLine":null,"hardMorning":true,"kickoff":{"key":"kickoff_morning","title":"t","subtitle":"s","finishTitle":null,"finishLine":null,"steps":[{"kind":"movement","label":"M","cardId":"a","title":"A","description":null},{"kind":"breathing","label":"B","cardId":"b","title":"B","description":null}]}}}"#)
        func row(wake: String?, run: KickoffRun? = nil) -> KickoffRow? {
            KickoffRowLogic.row(focus: hard, slot: .morning, morningCheckinDone: true, run: run, wakeTime: wake, calendar: utc)
        }
        #expect(row(wake: "06:45")?.dueAt == moment(7, 45))
        #expect(row(wake: nil)?.dueAt == moment(10, 0))
        // the table's own deadline stays fixed once offered, even if the wake time is edited later
        let offered = KickoffRun(day: "2026-11-13", focusCell: "P5", offeredAt: moment(7, 0), dueAt: moment(7, 45), completedAt: nil, stepsDone: 2)
        #expect(row(wake: "08:30", run: offered)?.dueAt == moment(7, 45))
        // another day's run is not today's
        let yesterday = KickoffRun(day: "2026-11-12", focusCell: "P5", offeredAt: moment(7, 0, day: 12), dueAt: moment(7, 45, day: 12), completedAt: moment(7, 20, day: 12), stepsDone: 6)
        #expect(row(wake: "06:45", run: yesterday)?.done == false)
    }

    @Test func theStatusIsDerivedOpenMissedDoneDoneLate() {
        let due = moment(7, 45)
        #expect(KickoffDeadline.status(dueAt: due, completedAt: nil, now: moment(7, 0)) == .open)
        #expect(KickoffDeadline.status(dueAt: due, completedAt: nil, now: moment(7, 45)) == .open)      // on the minute is still on time
        #expect(KickoffDeadline.status(dueAt: due, completedAt: nil, now: moment(7, 46)) == .missed)
        #expect(KickoffDeadline.status(dueAt: due, completedAt: moment(7, 20), now: moment(12, 0)) == .done)
        #expect(KickoffDeadline.status(dueAt: due, completedAt: moment(7, 45), now: moment(12, 0)) == .done)
        #expect(KickoffDeadline.status(dueAt: due, completedAt: moment(8, 30), now: moment(12, 0)) == .doneLate)
        #expect(KickoffDeadline.status(dueAt: nil, completedAt: moment(8, 30), now: moment(12, 0)) == .done)   // no deadline: never late
        #expect(KickoffDeadline.status(dueAt: nil, completedAt: nil, now: moment(23, 0)) == .open)
        let run = KickoffRun(day: "2026-11-13", focusCell: nil, offeredAt: moment(7, 0), dueAt: due, completedAt: nil, stepsDone: 0)
        #expect(run.status(now: moment(9, 0)) == .missed)
    }

    // MARK: The table

    @Test func theUpsertPayloadMatchesTheTablesColumns() throws {
        let run = KickoffRun(day: "2026-11-13", focusCell: "P5", offeredAt: moment(7, 0), dueAt: moment(7, 45), completedAt: nil, stepsDone: 0)
        let offer = KickoffRunLogic.offerColumns(run, patientId: "p-1")
        #expect(Set(offer.keys) == ["patient_id", "day", "routine", "focus_cell", "offered_at", "due_at", "steps_done"])   // no completed_at before a finish
        let data = try JSONEncoder().encode(offer)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["routine"] as? String == "kickoff_morning")
        #expect(object["patient_id"] as? String == "p-1")
        #expect(object["day"] as? String == "2026-11-13")
        #expect(object["focus_cell"] as? String == "P5")
        #expect(object["due_at"] as? String == "2026-11-13T07:45:00.000Z")
        #expect(object["steps_done"] as? Int == 0)

        var progressed = run
        progressed.stepsDone = 3
        #expect(Set(KickoffRunLogic.progressColumns(progressed, patientId: "p-1").keys) == ["patient_id", "day", "routine", "steps_done"])   // never the offer's columns

        var finished = progressed
        finished.stepsDone = 6
        finished.completedAt = moment(7, 30)
        let completion = KickoffRunLogic.completionColumns(finished, patientId: "p-1")
        #expect(Set(completion.keys) == ["patient_id", "day", "routine", "steps_done", "completed_at"])
        #expect(completion["completed_at"] == .string("2026-11-13T07:30:00.000Z"))

        // the table's check: steps_done between 0 and 20
        var long = run
        long.stepsDone = 99
        #expect(KickoffRunLogic.progressColumns(long, patientId: "p-1")["steps_done"] == .int(20))
    }

    @MainActor
    private func makeService(_ backend: StubBackend, defaults: UserDefaults, clock: Date) throws -> FocusService {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: MockTransport()), store: store)
        let auth = AuthService(sessions: sessions, state: AppState())
        return FocusService(backend: backend, auth: auth, defaults: defaults, now: { clock }, calendar: utc)
    }

    @MainActor
    private func isolatedDefaults() throws -> (UserDefaults, () -> Void) {
        let suite = "fa.test.kickoff.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    @MainActor
    @Test func offeringWritesTheDayOnceAndFinishingRecordsTheMoment() async throws {
        let (defaults, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let backend = StubBackend()
        let service = try makeService(backend, defaults: defaults, clock: moment(7, 0, day: 13))
        await service.load()   // the stub's focus is "2026-09-25": the run follows the focus day
        let day = try #require(service.focus?.day)
        await service.offerKickoff(patientId: "p-1") { "06:45" }
        await service.settleWrites()
        let run = try #require(service.kickoffRun)
        #expect(run.day == day)
        #expect(run.dueAt == KickoffDeadline.dueAt(day: day, wakeTime: "06:45", calendar: utc))
        #expect(backend.kickoffWrites.count == 1)
        #expect(backend.kickoffWrites[0]["due_at"] != nil)
        // shown again (the card re-renders): not written twice
        await service.offerKickoff(patientId: "p-1") { "06:45" }
        #expect(backend.kickoffWrites.count == 1)

        service.kickoffSteps(2)
        service.kickoffSteps(1)   // going back never lowers the count
        service.finishKickoff(steps: 6)
        service.finishKickoff(steps: 6)   // a second walk the same day does not move it
        await service.settleWrites()
        #expect(service.kickoffDone)
        #expect(service.kickoffRun?.stepsDone == 6)
        #expect(backend.kickoffWrites.count == 3)   // offer, steps, finish
        #expect(backend.kickoffWrites[1]["steps_done"] == .int(2))
        #expect(backend.kickoffWrites[2]["completed_at"] == .string("2026-11-13T07:00:00.000Z"))
    }

    @MainActor
    @Test func theTablesRowWinsAndAFailedWriteNeverBreaksTheWalk() async throws {
        let (defaults, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let backend = StubBackend()
        let service = try makeService(backend, defaults: defaults, clock: moment(9, 0))
        await service.load()
        let day = try #require(service.focus?.day)
        backend.kickoffRunResult = KickoffRun(day: day, focusCell: "P5", offeredAt: moment(7, 0), dueAt: moment(7, 45), completedAt: moment(7, 20), stepsDone: 6)
        await service.offerKickoff(patientId: "p-1") { nil }
        #expect(service.kickoffDone)
        #expect(backend.kickoffWrites.isEmpty)   // nothing to offer: the day already has its row

        // a write that fails: shown done all the same, kept on this phone, and sent again the next time the row is offered
        let (defaults2, cleanup2) = try isolatedDefaults()
        defer { cleanup2() }
        let failing = StubBackend()
        failing.kickoffWriteFails = true
        let second = try makeService(failing, defaults: defaults2, clock: moment(9, 0))
        await second.load()
        await second.offerKickoff(patientId: "p-1") { nil }
        second.finishKickoff(steps: 6)
        await second.settleWrites()
        #expect(second.kickoffDone)
        let secondDay = try #require(second.focus?.day)
        #expect(second.kickoffRun?.dueAt == KickoffDeadline.dueAt(day: secondDay, wakeTime: nil, calendar: utc))   // the 10:00 fallback
        let again = try makeService(failing, defaults: defaults2, clock: moment(9, 5))
        await again.load()
        await again.offerKickoff(patientId: "p-1") { nil }
        #expect(again.kickoffDone)   // from this phone's copy, the table could not be written
    }

    @MainActor
    @Test func aReadThatFailsNeverOverwritesTheTablesRow() async throws {
        let (defaults, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let backend = StubBackend()
        backend.kickoffReadFails = true
        let service = try makeService(backend, defaults: defaults, clock: moment(7, 0))
        await service.load()
        await service.offerKickoff(patientId: "p-1") { "06:45" }
        await service.settleWrites()
        #expect(service.kickoffRun != nil)       // the row still shows, from what the phone knows
        #expect(backend.kickoffWrites.isEmpty)   // but the offer is not sent over a row that may be finished
    }

    // MARK: The Foundation Track (owner, 2026-11-13)

    @Test func aTrackMemberGetsTheRoutineCardWithoutTheNoActionsPlace() {
        // the card is on Home from track day 2 (not on day 1, which is the welcome)
        #expect(TrackLogic.showsRoutine(trackDay: 2))
        #expect(TrackLogic.showsRoutine(trackDay: 14))
        #expect(!TrackLogic.showsRoutine(trackDay: 1))
        // no plan habits at all: the kickoff row (or the morning check-in) alone makes the card
        #expect(PlanTodayLogic.mode(onTrack: true, hasPlanHabits: false, hasKickoff: true, showsCheckin: false) == .card)
        #expect(PlanTodayLogic.mode(onTrack: true, hasPlanHabits: false, hasKickoff: false, showsCheckin: true) == .card)
        #expect(PlanTodayLogic.mode(onTrack: true, hasPlanHabits: true, hasKickoff: false, showsCheckin: false) == .card)
        // nothing to say: a track member sees no blurred place (their actions are in the track card); everyone else does
        #expect(PlanTodayLogic.mode(onTrack: true, hasPlanHabits: false, hasKickoff: false, showsCheckin: false) == .hidden)
        #expect(PlanTodayLogic.mode(onTrack: false, hasPlanHabits: false, hasKickoff: false, showsCheckin: false) == .placeholder)
        #expect(!PlanTodayLogic.showsNoActionsArea(onTrack: true, withCheckin: true, hasPlanHabits: false))
        #expect(PlanTodayLogic.showsNoActionsArea(onTrack: false, withCheckin: true, hasPlanHabits: false))
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
