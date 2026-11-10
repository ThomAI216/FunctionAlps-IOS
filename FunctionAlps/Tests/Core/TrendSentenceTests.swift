import Foundation
import Testing
@testable import FunctionAlps

/// The Trends sentence (owner-approved wording set, 2026-11-10): a pure choice from the member's own daily series.
@Suite("Trend sentence — steady, rising, dipped, or not enough data")
struct TrendSentenceTests {
    @Test("Fewer than four logged days is not enough data, however the days sit")
    func notEnoughData() {
        #expect(TrendSentence.classify([]) == .notEnoughData)
        #expect(TrendSentence.classify([60, nil, 62, nil, nil, 61, nil]) == .notEnoughData)
        #expect(TrendSentence.classify([nil, nil, nil, nil, nil, nil, nil]) == .notEnoughData)
    }

    @Test("A flat window is steady")
    func steady() {
        #expect(TrendSentence.classify([60, 62, 58, 61, 60, 62, 59, 61, 60, 61]) == .steady)
    }

    @Test("The last three days well above the window average read as rising")
    func rising() {
        #expect(TrendSentence.classify([50, 50, 52, 50, 51, 50, 50, 70, 72, 74]) == .rising)
    }

    @Test("The last three days well below the window average read as dipped")
    func dipped() {
        #expect(TrendSentence.classify([70, 72, 71, 70, 69, 71, 70, 50, 48, 52]) == .dipped)
    }

    @Test("The margin is eight points on the window average: 49 is steady, 48 is dipped")
    func margin() {
        // Seven days at 60, then three at x. Average = (420 + 3x) / 10.
        #expect(TrendSentence.classify([60, 60, 60, 60, 60, 60, 60, 49, 49, 49]) == .steady)   // 49 > 56.7 − 8
        #expect(TrendSentence.classify([60, 60, 60, 60, 60, 60, 60, 48, 48, 48]) == .dipped)   // 48 ≤ 56.4 − 8
        #expect(TrendSentence.classify([60, 60, 60, 60, 60, 60, 60, 71, 71, 71]) == .steady)   // 71 < 63.3 + 8
        #expect(TrendSentence.classify([60, 60, 60, 60, 60, 60, 60, 72, 72, 72]) == .rising)   // 72 ≥ 63.6 + 8
    }

    @Test("One logged day among the last three is not a trend")
    func oneRecentDay() {
        #expect(TrendSentence.classify([60, 60, 60, 60, 60, 60, 60, nil, nil, 20]) == .steady)
    }

    @Test("Missing days inside the window do not count as low days")
    func gapsAreNotLows() {
        #expect(TrendSentence.classify([60, nil, 60, nil, 60, nil, 60, nil, 60, 60]) == .steady)
    }

    @Test("Stress is read on calmness: a fall in calm is the stress sentence for a higher stress")
    func stressDirection() {
        // Stress LEVELS 4 4 4 4 4 4 4 7 7 8 = calm 60 60 60 60 60 60 60 30 30 20.
        let levels: [Double] = [4, 4, 4, 4, 4, 4, 4, 7, 7, 8]
        let calm: [Double?] = levels.map { 100 - $0 * 10 }
        #expect(TrendSentence.classify(calm) == .dipped)
        #expect(TrendSentence.sentence(for: .stress, goodness: calm) == TrendSentence.text(for: .stress, kind: .dipped))
        // The same shape on mood is a dip in mood, a different line.
        #expect(TrendSentence.sentence(for: .stress, goodness: calm) != TrendSentence.text(for: .mood, kind: .dipped))
        // Stress levels falling = calm rising = the easing line.
        let easing: [Double?] = [7, 7, 7, 7, 7, 7, 7, 4, 4, 3].map { 100 - $0 * 10 }
        #expect(TrendSentence.classify(easing) == .rising)
    }

    @Test("Every signal has its own line for every kind, and none is empty")
    func closedSet() {
        var seen = Set<String>()
        for signal in TrendSignal.allCases {
            for kind in [TrendKind.steady, .rising, .dipped] {
                let line = TrendSentence.text(for: signal, kind: kind)
                #expect(!line.isEmpty)
                #expect(seen.insert(line).inserted, "\(signal) \(kind) repeats another line")
            }
        }
        #expect(seen.count == 18)
        for signal in TrendSignal.allCases {
            #expect(!TrendSentence.text(for: signal, kind: .notEnoughData).isEmpty)
        }
    }
}
