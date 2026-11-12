import Foundation
import Testing
@testable import FunctionAlps

/// The rebuilt plan screens' pure logic (CLINICAL 2026-11-12): signal colours, the Monday-to-Sunday week, the week's
/// ticks on the focus and action pages, and which resource links a member may open.
@Suite("Plan screens — colours, week ticks, links")
struct PlanScreensTests {
    // MARK: Signal colours

    @Test("a line takes the colour of its signal: bloating brown, iron red, coffee blue, sleep indigo")
    func signalColours() {
        #expect(PlanScreensLogic.signalHex(for: "Your bloating is driven by fructans") == PlanScreensLogic.Tint.bloating)
        #expect(PlanScreensLogic.signalHex(for: "Low iron is adding to your afternoon tiredness") == PlanScreensLogic.Tint.iron)
        #expect(PlanScreensLogic.signalHex(for: "Your coffee timing may be reducing the effect") == PlanScreensLogic.Tint.coffee)
        #expect(PlanScreensLogic.signalHex(for: "sleep") == PlanScreensLogic.Tint.sleep)
    }

    @Test("an unknown signal keeps the brand forest, never an invented colour")
    func unknownSignalIsForest() {
        #expect(PlanScreensLogic.signalHex(for: nil) == PlanScreensLogic.Tint.forest)
        #expect(PlanScreensLogic.signalHex(for: "Something new") == PlanScreensLogic.Tint.forest)
    }

    @Test("the menopause programme is pink; the gut programme and others get their band")
    func bandColours() {
        #expect(PlanScreensLogic.bandHex(kind: "hormones_menopause") == PlanScreensLogic.Tint.menopause)
        #expect(PlanScreensLogic.bandHex(kind: "digestion") == PlanScreensLogic.Tint.focus)
        #expect(PlanScreensLogic.bandHex(kind: nil) == PlanScreensLogic.Tint.forest)
    }

    // MARK: Week

    @Test("the week of a Thursday runs Monday to Sunday")
    func weekOfThursday() {
        // 2026-11-12 is a Thursday.
        #expect(PlanScreensLogic.week(containing: "2026-11-12") == [
            "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15",
        ])
    }

    @Test("a Sunday belongs to the week that started six days before it, not the next one")
    func weekOfSunday() {
        let week = PlanScreensLogic.week(containing: "2026-11-15")
        #expect(week.first == "2026-11-09")
        #expect(week.last == "2026-11-15")
    }

    @Test("an unparseable day gives no week rather than a wrong one")
    func badDay() {
        #expect(PlanScreensLogic.week(containing: "not-a-day").isEmpty)
    }

    // MARK: Week ticks

    @Test("ticks mark only this habit's completions in the current week")
    func ticks() {
        let completions = [
            HabitCompletionRow(id: "c1", habitId: "h1", completionDate: "2026-11-09"),
            HabitCompletionRow(id: "c2", habitId: "h1", completionDate: "2026-11-12"),
            HabitCompletionRow(id: "c3", habitId: "h2", completionDate: "2026-11-10"),
            HabitCompletionRow(id: "c4", habitId: "h1", completionDate: "2026-11-02"), // last week
        ]
        let ticks = PlanScreensLogic.weekTicks(habitId: "h1", completions: completions, today: "2026-11-12")
        #expect(ticks.count == 7)
        #expect(ticks.filter(\.done).map(\.day) == ["2026-11-09", "2026-11-12"])
        #expect(PlanScreensLogic.doneCount(ticks) == 2)
    }

    // MARK: Resources and why

    private func habit(links: [HabitLinks.Entry], why: String?) -> HabitRow {
        var h = HabitRow(id: "h1", carePlanItemId: nil, title: "Walk", description: nil, frequencyRule: "FREQ=DAILY",
                         status: "active", source: "prescribed", pillar: nil, slot: "evening", appearsAfterHabitId: nil,
                         easyTitle: nil, easyDescription: nil, revTitle: nil, revDescription: nil,
                         createdAt: "2026-10-01T08:00:00Z", habitBankId: nil)
        h.resources = HabitLinks(links)
        h.generalWhy = why
        return h
    }

    @Test("only titled http(s) links are offered; app schemes, bad addresses and untitled entries are left out")
    func linksFiltered() {
        let entries = [
            HabitLinks.Entry(kind: "url", title: "Why a walk helps", url: "https://example.org/walk"),
            HabitLinks.Entry(kind: "url", title: "Plain web", url: "http://example.org/plain"),
            HabitLinks.Entry(kind: "url", title: "Phone link", url: "tel:+41000000"),
            HabitLinks.Entry(kind: "url", title: "Script", url: "javascript:alert(1)"),
            HabitLinks.Entry(kind: "url", title: "  ", url: "https://example.org/blank-title"),
            HabitLinks.Entry(kind: "url", title: "No address", url: nil),
        ]
        let titles = PlanScreensLogic.links(habit(links: entries, why: nil)).map(\.title)
        #expect(titles == ["Why a walk helps", "Plain web"])
    }

    @Test("a habit with no links has an empty list, which the page shows as an empty state")
    func noLinks() {
        #expect(PlanScreensLogic.links(habit(links: [], why: nil)).isEmpty)
    }

    @Test("the why is shown only when the habit has one, trimmed")
    func why() {
        #expect(PlanScreensLogic.why(habit(links: [], why: "  Eases dinner  ")) == "Eases dinner")
        #expect(PlanScreensLogic.why(habit(links: [], why: "   ")) == nil)
        #expect(PlanScreensLogic.why(habit(links: [], why: nil)) == nil)
    }
}
