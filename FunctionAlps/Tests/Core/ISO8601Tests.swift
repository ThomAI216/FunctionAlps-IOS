import Foundation
import Testing
@testable import FunctionAlps

@Suite("ISO8601 parsing (Postgres timestamps)")
struct ISO8601Tests {
    @Test func parsesSixDigitFraction() throws {
        let date = try #require(ISO8601.parse("2026-09-02T14:03:11.123456+00:00"))
        #expect(abs(date.timeIntervalSince1970 - 1_788_357_791.123) < 0.01)
    }

    @Test func parsesZuluWithoutFraction() throws {
        let date = try #require(ISO8601.parse("2026-09-02T14:03:11Z"))
        #expect(date.timeIntervalSince1970 == 1_788_357_791)
    }

    @Test func parsesDateOnly() {
        #expect(ISO8601.parse("2026-09-02") != nil)
    }

    @Test func truncatesOnlyLongFractions() {
        #expect(ISO8601.truncateFraction("2026-09-02T14:03:11.12Z") == "2026-09-02T14:03:11.12Z")
        #expect(ISO8601.truncateFraction("2026-09-02T14:03:11.123456+00:00") == "2026-09-02T14:03:11.123+00:00")
    }

    @Test func rejectsGarbage() {
        #expect(ISO8601.parse("yesterday") == nil)
    }
}
