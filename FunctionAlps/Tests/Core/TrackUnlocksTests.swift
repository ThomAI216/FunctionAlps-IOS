import Foundation
import Testing
@testable import FunctionAlps

/// Thomas, 2026-11-06: on the Foundation Track, Trends opens after 3 days in a row of using the app and Food with
/// the first meal; once open, a tab stays open.
@Suite("Foundation Track unlocks")
struct TrackUnlocksTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    @Test("A day counts with a functional check-in or a meal logged")
    func activeDays() {
        func row(_ day: String, done: Bool) -> DailyCheckin {
            DailyCheckin(day: day, functionalCompletedAt: done ? Date(timeIntervalSince1970: 1) : nil, gutCompletedAt: nil,
                         energy: nil, mood: nil, sleep: nil, calmness: nil, gutOverall: nil)
        }
        let checkins = [row("2026-11-03", done: true), row("2026-11-04", done: false)]
        let c = calendar
        let meal = c.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        #expect(TrackUnlocks.activeDays(checkins: checkins, mealDates: [meal], calendar: c) == ["2026-11-03", "2026-11-05"])
    }

    @Test("Trends: 3 days in a row open it, and it stays open after a gap")
    func trends() {
        #expect(!TrackUnlocks.trendsOpen([], calendar: calendar))
        #expect(!TrackUnlocks.trendsOpen(["2026-11-01", "2026-11-02", "2026-11-04"], calendar: calendar))
        #expect(TrackUnlocks.trendsOpen(["2026-11-01", "2026-11-02", "2026-11-03"], calendar: calendar))
        // An old run of 3 keeps it open even when today's run is 1.
        #expect(TrackUnlocks.trendsOpen(["2026-10-20", "2026-10-21", "2026-10-22", "2026-11-05"], calendar: calendar))
        // Across a month end.
        #expect(TrackUnlocks.trendsOpen(["2026-10-30", "2026-10-31", "2026-11-01"], calendar: calendar))
    }

    @Test("The run as of today: today, or yesterday while today has nothing yet")
    func currentRun() {
        let days: Set<String> = ["2026-11-04", "2026-11-05"]
        #expect(TrackUnlocks.currentRun(days, today: "2026-11-05", calendar: calendar) == 2)
        #expect(TrackUnlocks.currentRun(days, today: "2026-11-06", calendar: calendar) == 2)
        #expect(TrackUnlocks.currentRun(days, today: "2026-11-07", calendar: calendar) == 0)
    }

    @Test("Food: the first meal opens it")
    func food() {
        #expect(!TrackUnlocks.foodOpen(mealCount: 0))
        #expect(TrackUnlocks.foodOpen(mealCount: 1))
    }

    @Test("The tab: open off the track; checking until known; locked on the track until opened")
    func gate() {
        #expect(TrackLockGate.state(onTrack: false, known: false, open: false) == .open)
        #expect(TrackLockGate.state(onTrack: true, known: false, open: false) == .checking)
        #expect(TrackLockGate.state(onTrack: true, known: true, open: false) == .locked)
        #expect(TrackLockGate.state(onTrack: true, known: true, open: true) == .open)
    }
}
