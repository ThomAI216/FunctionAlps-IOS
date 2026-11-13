import Foundation
import Testing
@testable import FunctionAlps

/// "My health plan" reads the clinician's plan page (owner, 2026-11-10): goals, supplements, tests, review.
@Suite("CarePlanLogic — goals, supplements and tests of the health plan")
struct CarePlanDetailTests {
    private func item(_ id: String, title: String? = nil, domain: String? = nil, kind: String? = nil, instruction: String? = nil,
                      explanation: String? = nil, doseValue: Double? = nil, doseUnit: String? = nil, cadence: String? = nil) -> CarePlanItemRow {
        CarePlanItemRow(id: id, domain: domain, title: title, objective: nil, instructionText: instruction,
                        patientSafeExplanation: explanation, status: "pushed_to_app", sortOrder: nil, itemKind: kind,
                        cadence: cadence, frequencyText: nil, doseValue: doseValue, doseUnit: doseUnit)
    }

    private func goal(_ id: String, phase: String?, baseline: Double? = nil, target: Double? = nil, unit: String? = nil) -> CarePlan.Goal {
        CarePlan.Goal(id: id, statement: "Goal \(id)", phaseKey: phase, baseline: baseline, target: target, unit: unit, cadence: nil)
    }

    @Test("A test shows once ordered; a proposal or a cancelled order never reaches the member")
    func testStates() {
        #expect(CarePlanLogic.testState("ordered") == .ordered)
        #expect(CarePlanLogic.testState("pending") == .processing)
        #expect(CarePlanLogic.testState("received") == .processing)
        #expect(CarePlanLogic.testState("reviewed") == .resulted)
        #expect(CarePlanLogic.testState("proposed") == nil)
        #expect(CarePlanLogic.testState("cancelled") == nil)
    }

    @Test("A supplement whose plan the clinician stopped or paused is dropped; one with no plan row stays")
    func supplementsFollowThePlanRow() {
        let items = [item("a", title: "Magnesium", kind: "supplement_plan"), item("b", title: "Vitamin D", kind: "supplement_plan"),
                     item("c", title: "Omega-3", kind: "supplement_plan"), item("d", title: "Zinc", kind: "supplement_plan")]
        let plans = [SupplementPlanRow(carePlanItemId: "a", dosageText: "300 mg", frequencyText: "evening", status: "stopped"),
                     SupplementPlanRow(carePlanItemId: "b", dosageText: "2000 IU", frequencyText: "morning", status: "active"),
                     SupplementPlanRow(carePlanItemId: "c", dosageText: "1 g", frequencyText: "lunch", status: "paused")]
        let out = CarePlanLogic.buildSupplements(items, plans: plans)
        #expect(out.map(\.name) == ["Vitamin D", "Zinc"])
        #expect(out.first?.dosage == "2000 IU")
        #expect(out.last?.dosage == nil)
    }

    @Test("The plan row's dosage wins over the item's dose value")
    func planDosageWins() {
        let items = [item("a", title: "Magnesium", kind: "supplement_plan", doseValue: 100, doseUnit: "mg")]
        let withPlan = CarePlanLogic.buildSupplements(items, plans: [SupplementPlanRow(carePlanItemId: "a", dosageText: "300 mg", frequencyText: nil, status: "active")])
        #expect(withPlan.first?.dosage == "300 mg")
        let without = CarePlanLogic.buildSupplements(items, plans: [])
        #expect(without.first?.dosage == "100 mg")
    }

    @Test("Goals for now: plan-wide ones and the current phase's; no current phase means all of them")
    func goalsNow() {
        let goals = [goal("1", phase: nil), goal("2", phase: "p1"), goal("3", phase: "p2")]
        #expect(CarePlanLogic.goalsNow(goals, currentPhase: "p2").map(\.id) == ["1", "3"])
        #expect(CarePlanLogic.goalsNow(goals, currentPhase: nil).map(\.id) == ["1", "2", "3"])
    }

    @Test("A goal's range reads where the member starts and where the plan aims")
    func goalRange() {
        #expect(CarePlanLogic.goalRange(goal("1", phase: nil, baseline: 4, target: 7, unit: "/10")) == "4 → 7 /10")
        #expect(CarePlanLogic.goalRange(goal("2", phase: nil, baseline: 4.5, target: 7)) == "4.5 → 7")
        #expect(CarePlanLogic.goalRange(goal("3", phase: nil, target: 7)) != nil)
        #expect(CarePlanLogic.goalRange(goal("4", phase: nil)) == nil)
    }

    @Test("A supplement item never appears in the plan in detail")
    func sectionsSkipSupplements() {
        let rows = [item("a", title: "Magnesium", domain: "supplementation", kind: "supplement_plan", instruction: "Take magnesium"),
                    item("b", title: "Walk", domain: "exercise", instruction: "Walk after lunch")]
        let sections = CarePlanLogic.buildSections(rows)
        #expect(sections.count == 1)
        #expect(sections.first?.items.map(\.text) == ["Walk after lunch"])
    }
}
