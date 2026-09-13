import Foundation
import Testing
@testable import FunctionAlps

@Suite("RedFlags")
struct RedFlagsTests {
    @Test func fromColumnsToggleAndColumnNames() {
        var flags = RedFlags.from { flag in
            switch flag {
            case .fever: true
            case .blackStool: false
            default: nil // a missing column is "not raised"
            }
        }
        #expect(flags.any && flags.contains(.fever) && !flags.contains(.blackStool))
        flags.toggle(.fever)
        #expect(!flags.any && flags == .none)
        #expect(RedFlag.severeWorseningPain.column == "red_flag_severe_worsening_pain")
        #expect(RedFlag.allCases.count == 6)
    }

    @Test func aDayRowWithoutFlagsShowsNoSignpost() {
        let day = DailyCheckin(day: "2026-09-13", functionalCompletedAt: nil, gutCompletedAt: nil, energy: nil, mood: nil, sleep: nil, calmness: nil, gutOverall: nil)
        #expect(day.redFlags.any == false)
    }
}
