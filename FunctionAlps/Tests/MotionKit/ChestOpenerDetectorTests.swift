import Foundation
import Testing
@testable import FunctionAlps

@Suite("ChestOpenerDetector")
struct ChestOpenerDetectorTests {
    private typealias F = MotionFixtures

    /// Runs `ratios` (nil = wrists not visible) through a fresh detector; returns it for inspection.
    private func run(_ ratios: [Double?], detector: ChestOpenerDetector = ChestOpenerDetector()) -> ChestOpenerDetector {
        var d = detector
        for pose in F.frames(ratios) { _ = d.process(pose) }
        return d
    }

    @Test func aFullCloseOpenCloseCycleCountsExactlyOnce() {
        let d = run(F.hold(0.6, 15) + F.cycle() + F.hold(0.6, 15))
        #expect(d.reps == 1)
    }

    @Test func repeatedCyclesCountEachOnce() {
        let d = run(F.hold(0.6, 15) + F.cycle() + F.cycle() + F.cycle())
        #expect(d.reps == 3)
    }

    @Test func armsBySidesCountAsClosed() {
        // Hanging arms ≈ one shoulder width apart: still below the closed threshold.
        let d = run(F.hold(1.05, 15) + F.cycle(closed: 1.05, open: 2.6) + F.hold(1.05, 10))
        #expect(d.reps == 1)
    }

    @Test func aPartialOpeningIsNotARep() {
        let d = run(F.hold(0.6, 15) + F.cycle(closed: 0.6, open: 1.7) + F.hold(0.6, 15))
        #expect(d.reps == 0)
    }

    @Test func jitterWhileHoldingOpenAddsNothing() {
        // Open, then wobbling between 1.4 and 2.3 for two seconds: inside the band, never closed.
        let wobble: [Double?] = (0..<60).map { $0.isMultiple(of: 2) ? 1.4 : 2.3 }
        let d = run(F.hold(0.6, 15) + F.hold(2.6, 15) + wobble + F.hold(0.6, 15))
        #expect(d.reps == 1)
    }

    @Test func jitterAroundEitherThresholdNeverFlipsThePhase() {
        let aroundClosed: [Double?] = (0..<60).map { $0.isMultiple(of: 2) ? 1.2 : 1.3 }
        let aroundOpen: [Double?] = (0..<60).map { $0.isMultiple(of: 2) ? 1.75 : 1.85 }
        let d = run(F.hold(0.6, 15) + aroundClosed + aroundOpen + F.hold(0.6, 15))
        #expect(d.reps == 0)
    }

    @Test func pausesAtTheTopAndBottomStillCountOnce() {
        let d = run(F.hold(0.6, 60) + F.hold(2.6, 90) + F.hold(0.6, 60))
        #expect(d.reps == 1)
    }

    @Test func slowRepsCount() {
        let d = run(F.hold(0.6, 15) + F.cycle(seconds: 6) + F.cycle(seconds: 6))
        #expect(d.reps == 2)
    }

    @Test func startingWithArmsOpenIsHalfARep() {
        // Open from the first frame, then closed: the opening was never seen.
        var d = run(F.hold(2.6, 30) + F.hold(0.6, 30))
        #expect(d.reps == 0)
        for pose in F.frames(F.cycle(), start: 2) { _ = d.process(pose) }
        #expect(d.reps == 1)
    }

    @Test func aShortTrackingInterruptionIsSurvived() {
        // 0.2 s without wrists while open, then closed: the cycle was seen either side of the blink.
        let d = run(F.hold(0.6, 15) + F.hold(2.6, 15) + F.hold(nil, 6) + F.hold(0.6, 15))
        #expect(d.reps == 1)
    }

    @Test func aLongTrackingLossNeverCountsTheTransitionAcrossIt() {
        // Open, gone for a second, back closed: the closing was not seen.
        var d = run(F.hold(0.6, 15) + F.hold(2.6, 15) + F.hold(nil, 30) + F.hold(0.6, 30))
        #expect(d.reps == 0)
        for pose in F.frames(F.cycle(), start: 3) { _ = d.process(pose) }
        #expect(d.reps == 1)
    }

    @Test func aPoseReacquiredOpenIsNotARep() {
        // Closed, lost, reacquired already open, then closed again.
        let d = run(F.hold(0.6, 15) + F.hold(nil, 30) + F.hold(2.6, 30) + F.hold(0.6, 30))
        #expect(d.reps == 0)
    }

    @Test func trackingLossIsReported() {
        var d = ChestOpenerDetector()
        let update = d.process(F.chestPose(ratio: 1, at: 0, wrists: false))
        #expect(update == .trackingLost)
        let lowConfidence = d.process(F.chestPose(ratio: 2.6, at: 0.1, confidence: 0.1))
        #expect(lowConfidence == .trackingLost)
        #expect(d.reps == 0)
    }

    @Test func implausiblyFastRepsAreIgnored() {
        // Two cycles of 8 frames (≈0.27 s each): the second ends well inside the 0.8 s minimum interval.
        let burst: [Double?] = F.hold(2.6, 4) + F.hold(0.6, 4)
        let d = run(F.hold(0.6, 15) + burst + burst)
        #expect(d.reps == 1)
    }

    @Test func holdingOpenForeverIsNotARep() {
        let d = run(F.hold(0.6, 15) + F.hold(2.6, Int(16 * F.fps)) + F.hold(0.6, 15))
        #expect(d.reps == 0)
    }

    @Test func unrelatedMovementInsideTheClosedRangeCountsNothing() {
        var seed: UInt64 = 42
        let noise: [Double?] = (0..<300).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return 0.4 + Double(seed >> 33) / Double(1 << 31) * 1.2   // 0.4 … 1.6
        }
        let d = run(noise)
        #expect(d.reps == 0)
    }

    @Test func emitsRepUpdatesWithTheRunningTotal() {
        var d = ChestOpenerDetector()
        var updates: [MovementUpdate] = []
        for pose in F.frames(F.hold(0.6, 15) + F.cycle() + F.cycle()) {
            let u = d.process(pose)
            if case .rep = u { updates.append(u) }
        }
        #expect(updates == [.rep(1), .rep(2)])
    }

    @Test func resetForgetsCountAndPhase() {
        var d = run(F.hold(0.6, 15) + F.cycle())
        #expect(d.reps == 1)
        d.reset()
        #expect(d.reps == 0)
        #expect(d.readout.phase == "—")
    }

    @Test func versionAndSignature() {
        let d = ChestOpenerDetector()
        #expect(d.exerciseId == "chest_opener")
        #expect(d.detectorVersion == "chest_opener_v1.0")
        #expect(d.requiredJoints == [.leftWrist, .rightWrist, .leftShoulder, .rightShoulder])
        #expect(d.readout.enterThreshold > d.readout.exitThreshold)
    }
}
