import Foundation
import Testing
@testable import FunctionAlps

/// Trends' "taken per day" strips: one row per active supplement from `member_supplements().observance.strip`
/// (14 days, oldest first), trimmed to the window. The server decides what was due; this only counts the marks.
@Suite("Trends supplements: the taken-per-day strip")
struct TrendsSupplementsTests {
    /// Two moments a day. 14 days: the day-14 (today) one is still to take.
    private func fixture(status: String = "active", strip: String? = nil) -> String {
        var days: [String] = []
        for i in 0..<14 {
            let day = String(format: "2026-11-%02d", i + 1)
            let isToday = i == 13
            // days 1-8 both taken, day 9 one taken, day 10 not due, days 11-13 none taken, today none yet
            let due = i != 9
            let t1 = i < 9 || i == 8, t2 = i < 8
            days.append(#"{"date":"\#(day)","due":\#(due),"today":\#(isToday),"moments":[{"moment":"morning","taken":\#(t1 && !isToday)},{"moment":"evening","taken":\#(t2 && !isToday)}]}"#)
        }
        let stripJSON = strip ?? "[" + days.joined(separator: ",") + "]"
        return #"[{"id":"s1","name":"Omega-3","moments":["morning","evening"],"status":"\#(status)","observance":{"days":14,"due":24,"taken":16,"pct":0.6667,"band":"blue","strip":\#(stripJSON)}}]"#
    }

    private func supplements(_ json: String) throws -> [Supplement] {
        try JSON.decode([Supplement].self, from: Data(json.utf8))
    }

    @Test("The strip decodes day by day, oldest first, with each moment")
    func decodes() throws {
        let s = try supplements(fixture())[0]
        let strip = try #require(s.observance?.strip)
        #expect(strip.count == 14)
        #expect(strip.first?.date == "2026-11-01")
        #expect(strip.last?.today == true)
        #expect(strip[0].moments.map(\.moment) == ["morning", "evening"])
    }

    @Test("A 14-day window shows every day; counts are days fully taken of the days due, today included")
    func fortnight() throws {
        let rows = TrendsEngine.supplementRows(try supplements(fixture()), window: .fortnight)
        let row = try #require(rows.first)
        #expect(row.days.count == 14)
        // Days 1-8 taken (8), day 9 partial, day 10 not due, days 11-13 missed, today pending (counted, as on the
        // supplement page): due = 14 - 1 = 13
        #expect(row.taken == 8)
        #expect(row.due == 13)
    }

    @Test("A 7-day window keeps the last seven days; a 28-day window can only show the 14 the server counts")
    func windows() throws {
        let list = try supplements(fixture())
        let week = try #require(TrendsEngine.supplementRows(list, window: .week).first)
        #expect(week.days.count == 7)
        #expect(week.days.first?.date == "2026-11-08")
        // day 8 taken, day 9 partial, 10 not due, 11-13 missed, today due
        #expect(week.taken == 1)
        #expect(week.due == 6)
        let month = try #require(TrendsEngine.supplementRows(list, window: .month).first)
        #expect(month.days.count == 14)
    }

    @Test("Paused supplements and supplements without a strip are left out; none means no rows")
    func leftOut() throws {
        #expect(TrendsEngine.supplementRows(try supplements(fixture(status: "paused")), window: .fortnight).isEmpty)
        #expect(TrendsEngine.supplementRows(try supplements(fixture(strip: "[]")), window: .fortnight).isEmpty)
        #expect(TrendsEngine.supplementRows(try supplements(#"[{"id":"a","name":"Zinc"}]"#), window: .week).isEmpty)
        #expect(TrendsEngine.supplementRows([], window: .week).isEmpty)
    }

    @Test("Today with something still to take is pending, never missed")
    func todayPending() throws {
        let row = try #require(TrendsEngine.supplementRows(try supplements(fixture()), window: .week).first)
        #expect(SupplementLogic.mark(row.days[6]) == .pending)
        #expect(SupplementLogic.mark(row.days[0]) == .taken)
    }
}
