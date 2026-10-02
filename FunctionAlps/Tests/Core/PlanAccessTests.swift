import Foundation
import Testing
@testable import FunctionAlps

@Suite("Plan access — the foundation bank and the member's own actions")
struct PlanAccessTests {
    private func card(_ id: String, pillar: String?, rule: String? = nil) -> ActionCardRow {
        var c = ActionCardRow(id: id, title: "Card \(id)")
        c.pillar = pillar
        c.frequencyRule = rule
        return c
    }

    @Test func anOwnHabitStartsDailyUnlessTheCardSaysOtherwise() {
        let daily = PlanAccess.ownHabit(from: card("a", pillar: "sleep"), patientId: "p", locale: "en", slot: nil)
        #expect(daily.frequencyRule == "FREQ=DAILY")
        #expect(daily.slot == nil && daily.source == "self_initiated" && daily.habitBankId == "a")
        let weekly = PlanAccess.ownHabit(from: card("b", pillar: "exercise", rule: "FREQ=WEEKLY;BYDAY=MO,TH"), patientId: "p", locale: "en", slot: .morning)
        #expect(weekly.frequencyRule == "FREQ=WEEKLY;BYDAY=MO,TH")
        #expect(weekly.slot == "morning" && weekly.pillar == "exercise")
        let blank = PlanAccess.ownHabit(from: card("c", pillar: nil, rule: "  "), patientId: "p", locale: "en", slot: nil)
        #expect(blank.frequencyRule == "FREQ=DAILY")
    }

    @Test func theBankGroupsByPillarInTheBanksOrder() {
        let groups = PlanAccess.bankByPillar([card("1", pillar: "sleep"), card("2", pillar: "nutrition"), card("3", pillar: "sleep"), card("4", pillar: nil)])
        #expect(groups.map(\.pillar) == ["sleep", "nutrition", "other"])
        #expect(groups[0].cards.map(\.id) == ["1", "3"])
    }

    @Test func aCardAlreadyInThePlanIsFound() {
        let mine = HabitRow(id: "h", carePlanItemId: nil, title: "Mine", description: nil, frequencyRule: "FREQ=DAILY", status: "active",
                            source: "self_initiated", pillar: nil, slot: nil, appearsAfterHabitId: nil, easyTitle: nil, easyDescription: nil,
                            revTitle: nil, revDescription: nil, createdAt: "2026-10-01T08:00:00+00:00", habitBankId: "b-1")
        let plan = HabitPlan(day: "2026-10-02", header: nil, phases: [], habits: [mine], completions: [])
        #expect(PlanAccess.habit(for: "b-1", in: plan)?.id == "h")
        #expect(PlanAccess.habit(for: "b-2", in: plan) == nil)
        #expect(PlanAccess.habit(for: "b-1", in: nil) == nil)
    }

    @Test func aBankCardReadsOnItsOwn_withoutAHabit() {
        var c = card("b", pillar: "sleep")
        c.titleFr = "Lumières tamisées"
        c.howMd = "1. Dim the lights"
        let content = ActionCardLogic.content(card: c, habit: nil, locale: "fr")
        #expect(content.title == "Lumières tamisées")
        #expect(content.steps == ["Dim the lights"])
    }
}
