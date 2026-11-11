import Foundation
import Testing
@testable import FunctionAlps

/// The client's care plan (CLINICAL 2026-11-12): decoding the seven member RPCs, the shaping of status wording, progress and
/// empty states, and the service's four states.
@Suite("ClientCarePlan — decoding + shaping")
struct ClientCarePlanLogicTests {
    // MARK: fixtures (what the RPCs return: snake_case, jsonb nested)

    static let programmesJSON = """
    [{"id":"pg-2","kind":"hormones_menopause","title":"Menopause","status":"active","start_date":"2026-09-14","end_date":null,
      "planned_weeks":20,"position":2,
      "phases":[{"title":"Settle","week_start":1,"week_end":8,"sort_order":1},{"title":"Protect","week_start":9,"week_end":16,"sort_order":2},{"title":"Hold","week_start":17,"week_end":20,"sort_order":3}]},
     {"id":"pg-1","kind":"digestion","title":"Gut reset","status":"completed","start_date":"2026-01-05","end_date":"2026-04-27",
      "planned_weeks":16,"position":1,"phases":[]}]
    """
    static let objectivesJSON = """
    [{"id":"ob-1","programme_id":"pg-2","client_verbatim":"I want to feel more energised","statement":"Raise daytime energy","target_date":"2026-12-09",
      "progress_pct":null,"status":"active",
      "outcomes":[{"id":"oc-1","label":"Wake feeling 8/10","metric_key":"energy","comparator":">=","target_value":14,"baseline_value":0,"current_value":6,"unit":"days","due_date":"2026-11-25","status":"open","met_at":null},
                  {"id":"oc-2","label":"Bloating 3 or lower","metric_key":"bloating","comparator":"<=","target_value":3,"baseline_value":8,"current_value":5.5,"unit":null,"due_date":null,"status":"open","met_at":null},
                  {"id":"oc-3","label":"Run 10 km","metric_key":null,"comparator":null,"target_value":null,"baseline_value":null,"current_value":null,"unit":null,"due_date":null,"status":"met","met_at":"2026-11-01T08:00:00+00:00"}]},
     {"id":"ob-2","programme_id":"pg-2","client_verbatim":null,"statement":"Sleep through the night","target_date":null,"progress_pct":40,"status":"active","outcomes":[]}]
    """

    static func raw() throws -> ClientCarePlanRaw {
        ClientCarePlanRaw(
            programmes: try JSON.decode([ClientProgramme].self, from: Data(programmesJSON.utf8)),
            objectives: try JSON.decode([ClientObjective].self, from: Data(objectivesJSON.utf8)))
    }

    // MARK: decoding

    @Test func decodesProgrammesObjectivesAndNestedJsonb() throws {
        let raw = try Self.raw()
        #expect(raw.programmes.count == 2)
        #expect(raw.programmes[0].phases?.count == 3)
        #expect(raw.programmes[0].phases?[1].weekStart == 9)
        #expect(raw.objectives[0].outcomes?.count == 3)
        #expect(raw.objectives[0].outcomes?[0].targetValue == 14)
        #expect(raw.objectives[0].outcomes?[1].currentValue == 5.5)
        #expect(raw.objectives[0].outcomes?[2].metAt != nil)
        #expect(raw.objectives[1].progressPct == 40)
    }

    @Test func decodesTheOtherFiveRPCs() throws {
        let wins = try JSON.decode([ClientWin].self, from: Data(#"[{"id":"w1","programme_id":"pg-1","programme_title":"Gut reset","kind":"win","text":"Three weeks of daily walks","status":"achieved","achieved_at":"2026-11-09","shared_at":"2026-11-10T09:00:00+00:00"}]"#.utf8))
        #expect(wins.first?.text == "Three weeks of daily walks")
        let complaints = try JSON.decode([ClientComplaint].self, from: Data(#"[{"id":"c1","programme_id":null,"signal_key":"energy","complaint_label":"Afternoon crashes","status":"in_progress","client_summary":"Fewer crashes","shared_at":"2026-11-10T09:00:00+00:00"}]"#.utf8))
        #expect(complaints.first?.signalKey == "energy")
        let hyp = try JSON.decode([ClientHypothesis].self, from: Data(#"[{"id":"h1","programme_id":null,"title":"Gut bacteria","explanation":"x","how_we_know":"y","resources":[{"kind":"article","title":"Read","url":"https://example.org/a"}],"lifecycle":"active","lifecycle_at":null,"proposed_by_first_name":"Thomas","shared_at":"2026-11-10T09:00:00+00:00"}]"#.utf8))
        #expect(hyp.first?.resources?.entries.first?.url == "https://example.org/a")
        let hypNull = try JSON.decode([ClientHypothesis].self, from: Data(#"[{"id":"h2","title":"T","resources":null}]"#.utf8))
        #expect(hypNull.first?.resources == nil)
        let evo = try JSON.decode([ClientEvolution].self, from: Data(#"[{"id":"e1","signal_key":"energy","complaint_label":null,"cause_kind":"action","cause_label":"Lunch walk","before_value":4,"after_value":7.5,"unit":"/10","direction":"improved","client_text":"Steadier afternoons","validated_at":"2026-11-10T09:00:00+00:00","shared_at":"2026-11-10T09:00:00+00:00"}]"#.utf8))
        #expect(ClientCarePlanLogic.beforeAfter(evo[0]) == "4 → 7.5 /10")
        let sit = try JSON.decode([ClientSituation].self, from: Data(#"[{"programme_id":"pg-1","title":"Gut reset","kind":"digestion","status":"active","start_date":"2026-01-05","situation_text":"Bloated daily","baseline":{"bloating":7},"shared_at":"2026-11-10T09:00:00+00:00"}]"#.utf8))
        #expect(sit.first?.situationText == "Bloated daily")
    }

    // MARK: programme, week, phase

    @Test func weekAndPhaseFollowTheStartDate() throws {
        let raw = try Self.raw()
        let programme = try #require(ClientCarePlanLogic.leadProgramme(raw))
        #expect(programme.id == "pg-2", "the first ACTIVE programme leads, not the first listed")
        #expect(ClientCarePlanLogic.week(of: programme, today: "2026-09-14") == 1)
        #expect(ClientCarePlanLogic.week(of: programme, today: "2026-09-20") == 1)
        #expect(ClientCarePlanLogic.week(of: programme, today: "2026-11-11") == 9)
        #expect(ClientCarePlanLogic.week(of: programme, today: "2026-09-01") == nil, "not started yet")
        #expect(ClientCarePlanLogic.totalWeeks(of: programme) == 20)
        let phase = try #require(ClientCarePlanLogic.currentPhase(programme, week: 9))
        #expect(phase.number == 2 && phase.of == 3 && phase.title == "Protect")
        let states = ClientCarePlanLogic.phaseSteps(programme, week: 9).map(\.state)
        #expect(states == [.done, .current, .upcoming])
        #expect(ClientCarePlanLogic.phaseSteps(programme, week: nil).map(\.state) == [.upcoming, .upcoming, .upcoming])
        #expect(ClientCarePlanLogic.currentPhase(programme, week: 25) == nil, "past the last phase's end nothing is current")
    }

    @Test func programmesAreOrderedAndJourneyNeedsMoreThanOne() throws {
        let raw = try Self.raw()
        #expect(ClientCarePlanLogic.ordered(raw.programmes).map(\.id) == ["pg-1", "pg-2"])
        #expect(ClientCarePlanLogic.showsJourney(raw))
        var single = raw; single.programmes = [raw.programmes[0]]
        #expect(!ClientCarePlanLogic.showsJourney(single))
        #expect(ClientCarePlanLogic.leadProgramme(.empty) == nil)
    }

    @Test func totalWeeksFallsBackToTheLastPhaseEnd() {
        let p = ClientProgramme(id: "x", kind: nil, title: "T", status: "active", startDate: nil, endDate: nil, plannedWeeks: nil, position: nil,
                                phases: [ClientPhase(title: "a", weekStart: 1, weekEnd: 6, sortOrder: 1), ClientPhase(title: "b", weekStart: 7, weekEnd: 12, sortOrder: 2)])
        #expect(ClientCarePlanLogic.totalWeeks(of: p) == 12)
    }

    // MARK: objectives and progress

    @Test func objectiveReadsInTheClientsOwnWordsFirst() throws {
        let raw = try Self.raw()
        #expect(ClientCarePlanLogic.title(raw.objectives[0]) == "I want to feel more energised")
        #expect(ClientCarePlanLogic.usesOwnWords(raw.objectives[0]))
        #expect(ClientCarePlanLogic.title(raw.objectives[1]) == "Sleep through the night")
        #expect(!ClientCarePlanLogic.usesOwnWords(raw.objectives[1]))
    }

    @Test func outcomeProgressWorksUpAndDown() throws {
        let lines = ClientCarePlanLogic.lines(try Self.raw().objectives[0])
        #expect(lines.count == 3)
        // up to 14 from 0, now 6
        #expect(abs(lines[0].fraction - 6.0 / 14.0) < 0.0001)
        #expect(ClientCarePlanLogic.progressText(lines[0]) == "6 of 14 days")
        // down to 3 from 8, now 5.5: halfway
        #expect(abs(lines[1].fraction - 0.5) < 0.0001)
        #expect(ClientCarePlanLogic.progressText(lines[1]) == "now 5.5 · target 3")
        // met without numbers
        #expect(lines[2].met && lines[2].fraction == 1)
        #expect(ClientCarePlanLogic.progressText(lines[2]) == "Reached")
    }

    @Test func progressIsClampedAndSurvivesMissingNumbers() {
        let over = ClientOutcome(id: "a", label: "x", metricKey: nil, comparator: ">=", targetValue: 10, baselineValue: 0, currentValue: 14, unit: nil, dueDate: nil, status: "open", metAt: nil)
        #expect(ClientCarePlanLogic.line(over).fraction == 1)
        let backwards = ClientOutcome(id: "b", label: "x", metricKey: nil, comparator: ">=", targetValue: 10, baselineValue: 5, currentValue: 2, unit: nil, dueDate: nil, status: "open", metAt: nil)
        #expect(ClientCarePlanLogic.line(backwards).fraction == 0)
        let empty = ClientOutcome(id: "c", label: "x", metricKey: nil, comparator: nil, targetValue: nil, baselineValue: nil, currentValue: nil, unit: nil, dueDate: nil, status: "open", metAt: nil)
        #expect(ClientCarePlanLogic.line(empty).fraction == 0)
        #expect(ClientCarePlanLogic.progressText(ClientCarePlanLogic.line(empty)) == "In progress")
    }

    @Test func objectiveProgressUsesThePracticesPercentThenTheOutcomes() throws {
        let raw = try Self.raw()
        #expect(ClientCarePlanLogic.progress(raw.objectives[1]) == 0.4)
        let mean = try #require(ClientCarePlanLogic.progress(raw.objectives[0]))
        #expect(abs(mean - (6.0 / 14.0 + 0.5 + 1.0) / 3.0) < 0.0001)
        let none = ClientObjective(id: "n", programmeId: nil, clientVerbatim: nil, statement: "s", targetDate: nil, progressPct: nil, status: "active", outcomes: [])
        #expect(ClientCarePlanLogic.progress(none) == nil)
        let m = ClientCarePlanLogic.milestones(raw.objectives[0])
        #expect(m.met == 1 && m.total == 3)
    }

    @Test func nextCheckIsTheEarliestOpenDueDateElseTheTarget() throws {
        let raw = try Self.raw()
        #expect(ClientCarePlanLogic.nextCheck(raw.objectives[0]) == "2026-11-25")
        #expect(ClientCarePlanLogic.nextCheck(raw.objectives[1]) == nil)
    }

    @Test func achievedObjectivesSortLast() throws {
        var raw = try Self.raw()
        raw.objectives[0] = ClientObjective(id: "ob-1", programmeId: "pg-2", clientVerbatim: "a", statement: nil, targetDate: nil, progressPct: 100, status: "achieved", outcomes: [])
        #expect(ClientCarePlanLogic.objectives(raw).map(\.id) == ["ob-2", "ob-1"])
    }

    @Test func theNudgeLeadsWithTheLineClosestToDone() throws {
        let nudge = try #require(ClientCarePlanLogic.nudge(try Self.raw()))
        #expect(nudge.objectiveId == "ob-1")
        #expect(nudge.line.label == "Bloating 3 or lower", "50% beats 43%")
        #expect(nudge.remaining == nil, "lower-is-better has no 'N more'")
        #expect(nudge.nextCheck == "2026-11-25")
        #expect(ClientCarePlanLogic.nudge(.empty) == nil)
    }

    // MARK: wins

    @Test func winsAreNewestFirstAndBlankOnesDropped() {
        func win(_ id: String, _ text: String?, _ at: String?) -> ClientWin {
            ClientWin(id: id, programmeId: nil, programmeTitle: nil, kind: "win", text: text, status: "achieved", achievedAt: at, sharedAt: nil)
        }
        var raw = ClientCarePlanRaw.empty
        raw.wins = [win("a", "April", "2026-04-12"), win("b", "  ", "2026-11-09"), win("c", "November", "2026-11-08"), win("d", "Undated", nil)]
        #expect(ClientCarePlanLogic.wins(raw).map(\.id) == ["c", "a", "d"])
        #expect(ClientCarePlanLogic.latestWin(raw)?.text == "November")
        #expect(ClientCarePlanLogic.latestWin(.empty) == nil)
    }

    // MARK: complaints, evolution, curve

    @Test func statusWordingIsTheThreeWordsThePracticeChose() {
        #expect(ClientCarePlanLogic.ComplaintStatus("managed").label == "Managed")
        #expect(ClientCarePlanLogic.ComplaintStatus("in_progress").label == "Being taken care of")
        #expect(ClientCarePlanLogic.ComplaintStatus("not_yet").label == "Not yet managed")
        #expect(ClientCarePlanLogic.ComplaintStatus(nil).label == "Being taken care of", "unknown reads as the middle state, never as managed")
        #expect(Set([ClientCarePlanLogic.ComplaintStatus.managed, .inProgress, .notYet].map(\.symbol)).count == 3, "never colour alone")
    }

    @Test func evolutionMatchesAComplaintBySignalThenByLabel() {
        func complaint(_ key: String?, _ label: String?) -> ClientComplaint {
            ClientComplaint(id: "c", programmeId: nil, signalKey: key, complaintLabel: label, status: "managed", clientSummary: nil, sharedAt: nil)
        }
        func evo(_ id: String, _ key: String?, _ label: String?) -> ClientEvolution {
            ClientEvolution(id: id, programmeId: nil, signalKey: key, complaintLabel: label, causeKind: "action", causeLabel: "Walk", beforeFrom: nil, beforeTo: nil, afterFrom: nil, afterTo: nil,
                            beforeValue: nil, afterValue: nil, unit: nil, direction: "improved", clientText: "t", validatedAt: nil, sharedAt: nil)
        }
        var raw = ClientCarePlanRaw.empty
        raw.evolution = [evo("1", "energy", nil), evo("2", nil, "Bloating"), evo("3", "sleep", nil)]
        #expect(ClientCarePlanLogic.evolution(for: complaint("energy", "Crashes"), in: raw).map(\.id) == ["1"])
        #expect(ClientCarePlanLogic.evolution(for: complaint(nil, "bloating"), in: raw).map(\.id) == ["2"])
        #expect(ClientCarePlanLogic.evolution(for: complaint(nil, nil), in: raw).isEmpty)
        #expect(ClientCarePlanLogic.name(complaint("energy_dip", nil)) == "Energy Dip")
    }

    private func day(_ n: Int, energy: Int?) -> DailyCheckin {
        DailyCheckin(day: String(format: "2026-11-%02d", n), functionalCompletedAt: nil, gutCompletedAt: nil, energy: energy, mood: 50, sleep: nil, calmness: nil, gutOverall: nil)
    }

    @Test func theMiniCurveOnlyDrawsForASignalTheCheckinHolds() {
        let history = [day(3, energy: 40), day(1, energy: 30), day(2, energy: nil), day(4, energy: 55), day(5, energy: 60)]
        #expect(ClientCarePlanLogic.series(signalKey: "energy", history: history) == [30, 40, 55, 60], "oldest first, gaps skipped")
        #expect(ClientCarePlanLogic.series(signalKey: nil, label: "Low Energy", history: history).count == 4)
        #expect(ClientCarePlanLogic.series(signalKey: "joint_pain", history: history).isEmpty, "no check-in column: no curve")
        #expect(ClientCarePlanLogic.series(signalKey: "sleep", history: history).isEmpty, "all nil")
        #expect(ClientCarePlanLogic.series(signalKey: "energy", history: Array(history.prefix(2))).isEmpty, "two points is a dot, not a trend")
        #expect(ClientCarePlanLogic.series(signalKey: "energy", history: []).isEmpty)
    }

    @Test func miniCurvePointsStayInsideTheBoxAndRiseWithTheValues() {
        let pts = MiniCurve.points([10, 50, 90], in: CGSize(width: 64, height: 22))
        #expect(pts.count == 3)
        #expect(pts.allSatisfy { $0.x >= 0 && $0.x <= 64 && $0.y >= 0 && $0.y <= 22 })
        #expect(pts[2].y < pts[0].y, "higher value, higher on screen (smaller y)")
        #expect(MiniCurve.points([50], in: CGSize(width: 64, height: 22)).isEmpty)
    }

    // MARK: this week's focus

    private func habit(_ id: String, item: String?, source: String) throws -> HabitRow {
        let json = """
        {"id":"\(id)","care_plan_item_id":\(item.map { "\"\($0)\"" } ?? "null"),"title":"T\(id)","description":null,"frequency_rule":"FREQ=DAILY","status":"active","source":"\(source)",
         "pillar":null,"slot":null,"appears_after_habit_id":null,"easy_title":null,"easy_description":null,"rev_title":null,"rev_description":null,"created_at":"2026-09-01T07:00:00+00:00"}
        """
        return try JSON.decode(HabitRow.self, from: Data(json.utf8))
    }

    private func action(_ id: String) -> HabitAction {
        HabitAction(id: id, title: "T\(id)", detail: nil, slot: nil, completionId: nil, streak: 0)
    }

    @Test func focusIsTheHabitsBehindAWeeklyFocusItemElsePrescribed() throws {
        var plan = HabitPlan(day: "2026-11-11", header: nil, phases: [],
                             habits: [try habit("h1", item: "i1", source: "prescribed"), try habit("h2", item: "i2", source: "prescribed"),
                                      try habit("h3", item: nil, source: "self_initiated")],
                             completions: [])
        let actions = [action("h1"), action("h2"), action("h3")]
        #expect(ClientCarePlanLogic.focusActions(plan, actions: actions).map(\.id) == ["h1", "h2"], "no focus flagged: the prescribed ones, not the member's own")
        plan.focusItemIds = ["i2"]
        #expect(ClientCarePlanLogic.focusActions(plan, actions: actions).map(\.id) == ["h2"])
        #expect(ClientCarePlanLogic.focusActions(plan, actions: [], limit: 3).isEmpty)
        plan.focusItemIds = []
        #expect(ClientCarePlanLogic.focusActions(plan, actions: actions, limit: 1).count == 1)
    }

    // MARK: empty

    @Test func nothingSharedReadsAsEmpty() {
        #expect(ClientCarePlanRaw.empty.isEmpty)
        var r = ClientCarePlanRaw.empty
        r.wins = [ClientWin(id: "w", programmeId: nil, programmeTitle: nil, kind: nil, text: "x", status: nil, achievedAt: nil, sharedAt: nil)]
        #expect(!r.isEmpty)
    }
}

@Suite("ClientCarePlan — the seven RPCs")
struct ClientCarePlanBackendTests {
    private func make(_ transport: MockTransport) -> SupabaseBackend {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: transport), store: store)
        let requester = AuthorizedRequester(sessions: sessions, transport: transport)
        return SupabaseBackend(
            rest: PostgRESTClient(environment: Fixtures.environment, requester: requester),
            functions: EdgeFunctionClient(environment: Fixtures.environment, requester: requester),
            storage: StorageClient(environment: Fixtures.environment, requester: requester))
    }

    /// Seven concurrent reads arrive in no fixed order, so every scripted handler answers by path.
    private func enqueueSeven(_ transport: MockTransport, failing: Set<String> = []) {
        let programmes = ClientCarePlanLogicTests.programmesJSON, objectives = ClientCarePlanLogicTests.objectivesJSON
        for _ in 0..<7 {
            transport.enqueue { request in
                let name = request.url.lastPathComponent
                if failing.contains(name) { return HTTPResponse(status: 404, headers: [:], body: Data(#"{"message":"function not found"}"#.utf8)) }
                let body: String = switch name {
                case "member_care_plan_programmes": programmes
                case "member_care_plan_objectives": objectives
                case "member_care_plan_wins": #"[{"id":"w1","text":"A win","achieved_at":"2026-11-09"}]"#
                default: "[]"
                }
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
            }
        }
    }

    @Test func readsTheSevenFunctionsUnderTheMembersSession() async throws {
        let transport = MockTransport()
        enqueueSeven(transport)
        let raw = try await make(transport).clientCarePlan()
        #expect(raw.programmes.count == 2 && raw.objectives.count == 2 && raw.wins.count == 1)
        let names = Set(transport.requests.map { $0.url.lastPathComponent })
        #expect(names == ["member_care_plan_programmes", "member_care_plan_objectives", "member_care_plan_wins", "member_care_plan_complaints",
                          "member_care_plan_hypotheses", "member_care_plan_evolution", "member_care_plan_situation"])
        #expect(transport.requests.allSatisfy { $0.method == .post && $0.url.path.hasPrefix("/rest/v1/rpc/") })
    }

    @Test func anExtraFailingSoftensToEmptyButProgrammesDoNot() async throws {
        let soft = MockTransport()
        enqueueSeven(soft, failing: ["member_care_plan_hypotheses", "member_care_plan_evolution"])
        let raw = try await make(soft).clientCarePlan()
        #expect(raw.hypotheses.isEmpty && raw.evolution.isEmpty && raw.programmes.count == 2)

        let hard = MockTransport()
        enqueueSeven(hard, failing: ["member_care_plan_programmes"])
        await #expect(throws: AppError.self) { _ = try await make(hard).clientCarePlan() }
    }
}

@Suite("ClientCarePlanService — states")
@MainActor
struct ClientCarePlanServiceTests {
    private func make(_ backend: StubBackend) -> ClientCarePlanService {
        let store = InMemorySessionStore(session: Fixtures.session(expiresAt: .distantFuture))
        let sessions = SessionManager(auth: SupabaseAuthClient(environment: Fixtures.environment, transport: MockTransport()), store: store)
        return ClientCarePlanService(backend: backend, members: MemberService(sessions: sessions, backend: backend),
                                     auth: AuthService(sessions: sessions, state: AppState()))
    }

    @Test func emptyWhenNothingIsSharedLoadedWhenSomethingIs() async throws {
        let backend = StubBackend()
        backend.patientId = "patient-a"
        let service = make(backend)
        #expect(service.state == .loading)
        await service.load()
        #expect(service.state == .empty)

        backend.clientPlanResult = try ClientCarePlanLogicTests.raw()
        await service.load(force: true)
        #expect(service.plan?.programmes.count == 2)
    }

    @Test func loadsOnceUntilForcedAndKeepsWhatItHasWhenARefreshFails() async throws {
        let backend = StubBackend()
        backend.patientId = "patient-a"
        backend.clientPlanResult = try ClientCarePlanLogicTests.raw()
        let service = make(backend)
        await service.load()
        await service.load()
        #expect(backend.clientPlanCalls == 1)
        backend.clientPlanError = .offline
        await service.load(force: true)
        #expect(service.plan?.programmes.count == 2, "a failed refresh keeps the plan on screen")
    }

    @Test func aFirstFailureIsShownAndAnotherPatientNeverSeesTheCache() async throws {
        let backend = StubBackend()
        backend.patientId = "patient-a"
        backend.clientPlanError = .server(status: 500)
        let service = make(backend)
        await service.load()
        #expect(service.state == .failed(.server(status: 500)))

        backend.clientPlanError = nil
        backend.clientPlanResult = try ClientCarePlanLogicTests.raw()
        await service.load(force: true)
        #expect(service.plan != nil)
        backend.patientId = "patient-b"
        backend.clientPlanResult = .empty
        await service.load(force: true)
        #expect(service.state == .empty)
        service.forget()
        #expect(service.state == .loading)
    }
}
