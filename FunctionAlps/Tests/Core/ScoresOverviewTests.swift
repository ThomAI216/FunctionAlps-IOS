import Foundation
import Testing
@testable import FunctionAlps

struct ScoresOverviewTests {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }()
    private let now = Date(timeIntervalSince1970: 1_788_350_400) // 2026-09-02T12:00:00Z

    @Test func dayKeysEndToday() {
        let keys = ScoresOverview.dayKeys(days: 14, now: now, calendar: cal)
        #expect(keys.count == 14 && keys.last == "2026-09-02" && keys.first == "2026-08-20")
    }

    @Test func bodySignalReadsTodayAndLeavesGapsNil() {
        let rows = [
            DailyCheckin(day: "2026-09-02", functionalCompletedAt: now, gutCompletedAt: nil, energy: 72, mood: 60, sleep: nil, calmness: 55, gutOverall: nil),
            DailyCheckin(day: "2026-08-30", functionalCompletedAt: now, gutCompletedAt: nil, energy: 40, mood: 50, sleep: 80, calmness: 70, gutOverall: nil),
        ]
        let energy = ScoresOverview.body(.energy, checkins: rows, now: now, calendar: cal)
        #expect(energy.score == 72)
        #expect(energy.series.count == 14 && energy.series[10] == 40 && energy.series[12] == nil)
        let sleep = ScoresOverview.body(.sleep, checkins: rows, now: now, calendar: cal)
        #expect(sleep.score == nil)                 // today's row has no sleep → nothing, never yesterday's
        #expect(ScoresOverview.body(.stress, checkins: rows, now: now, calendar: cal).score == 55) // calmness, higher = better
    }

    @Test func gutSignalUsesTheThreeSubScores() {
        let days = [GutDay(day: "2026-09-02", comfort: 65, stool: 80, reactions: nil, overall: 70, stoolQuality: nil, stoolFrequency: nil, completedAt: now)]
        #expect(ScoresOverview.gut(.comfort, days: days, now: now, calendar: cal).score == 65)
        #expect(ScoresOverview.gut(.stool, days: days, now: now, calendar: cal).score == 80)
        #expect(ScoresOverview.gut(.reactions, days: days, now: now, calendar: cal).score == nil)
    }

    @Test func statusBandsMatchTheWeb() {
        #expect(ScoreStatus.of(nil) == .watch)
        #expect(ScoreStatus.of(67) == .good && ScoreStatus.of(66) == .watch && ScoreStatus.of(34) == .watch && ScoreStatus.of(33) == .bad)
    }
}
