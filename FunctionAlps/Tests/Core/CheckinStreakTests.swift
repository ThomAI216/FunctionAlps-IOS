import Foundation
import Testing
@testable import FunctionAlps

@Suite("CheckinStreak")
struct CheckinStreakTests {
    private func row(_ day: String, done: Bool = true) -> DailyCheckin {
        DailyCheckin(day: day, functionalCompletedAt: done ? Date() : nil, gutCompletedAt: nil, energy: nil, mood: nil, sleep: nil, calmness: nil, gutOverall: nil)
    }

    @Test func countsConsecutiveDaysEndingToday() {
        let h = [row("2026-09-02"), row("2026-09-03"), row("2026-09-04")]
        #expect(CheckinStreak.days(history: h, todayDone: true, today: "2026-09-05") == 4)
        #expect(CheckinStreak.days(history: h, todayDone: false, today: "2026-09-05") == 3)
    }

    @Test func todayNotDoneKeepsLastNightsStreak() {
        let h = [row("2026-09-04")]
        #expect(CheckinStreak.days(history: h, todayDone: false, today: "2026-09-05") == 1)
    }

    @Test func gapBreaksTheChain() {
        let h = [row("2026-09-01"), row("2026-09-02"), row("2026-09-04")]
        #expect(CheckinStreak.days(history: h, todayDone: true, today: "2026-09-05") == 2)
        // A day row without the functional stamp (gut only) does not count.
        let g = [row("2026-09-04", done: false)]
        #expect(CheckinStreak.days(history: g, todayDone: false, today: "2026-09-05") == 0)
    }

    @Test func nothingIsZero() {
        #expect(CheckinStreak.days(history: [], todayDone: false, today: "2026-09-05") == 0)
        #expect(CheckinStreak.days(history: [], todayDone: false, today: "bogus") == 0)
    }
}
