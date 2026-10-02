import Foundation
import Testing
@testable import FunctionAlps

@Suite("OneEuroFilter")
struct OneEuroFilterTests {
    @Test func firstSamplePassesThrough() {
        var f = OneEuroFilter(minCutoff: 1, beta: 0)
        #expect(f.filter(0.42, at: 0) == 0.42)
    }

    @Test func aConstantSignalStaysPut() {
        var f = OneEuroFilter(minCutoff: 1, beta: 1)
        var out = 0.0
        for i in 0..<60 { out = f.filter(0.5, at: Double(i) / 30) }
        #expect(abs(out - 0.5) < 1e-12)
    }

    @Test func jitterAtRestIsDamped() {
        var f = OneEuroFilter(minCutoff: 1, beta: 0.5)
        var outputs: [Double] = []
        for i in 0..<120 {
            let raw = 0.5 + (i.isMultiple(of: 2) ? 0.01 : -0.01)
            outputs.append(f.filter(raw, at: Double(i) / 30))
        }
        let tail = outputs.suffix(60)
        let spread = (tail.max() ?? 0) - (tail.min() ?? 0)
        #expect(spread < 0.01)   // raw spread is 0.02
    }

    @Test func betaFollowsFastMovesWithLessLag() {
        var still = OneEuroFilter(minCutoff: 1, beta: 0)
        var responsive = OneEuroFilter(minCutoff: 1, beta: 10)
        _ = still.filter(0, at: 0)
        _ = responsive.filter(0, at: 0)
        var a = 0.0, b = 0.0
        for i in 1...6 {
            a = still.filter(1, at: Double(i) / 30)
            b = responsive.filter(1, at: Double(i) / 30)
        }
        #expect(b > a)
        #expect(b > 0.5)
    }

    @Test func timeThatDoesNotAdvanceReturnsTheLastOutput() {
        var f = OneEuroFilter(minCutoff: 1, beta: 0)
        _ = f.filter(0, at: 1)
        let last = f.filter(1, at: 1.1)
        #expect(f.filter(5, at: 1.1) == last)
        #expect(f.filter(5, at: 0.5) == last)
    }

    @Test func resetStartsOver() {
        var f = OneEuroFilter(minCutoff: 1, beta: 0)
        _ = f.filter(0, at: 0)
        _ = f.filter(1, at: 0.1)
        f.reset()
        #expect(f.filter(0.7, at: 0.2) == 0.7)
    }
}

@Suite("PoseSmoother")
struct PoseSmootherTests {
    @Test func lowConfidenceJointsAreDroppedNotInvented() {
        var s = PoseSmoother(minimumConfidence: 0.3)
        let pose = NormalizedPose(timestamp: 0, points: [
            .leftWrist: PosePoint(x: 0.2, y: 0.5, confidence: 0.9),
            .rightWrist: PosePoint(x: 0.8, y: 0.5, confidence: 0.1),
        ])
        let out = s.smooth(pose)
        #expect(out[.leftWrist] != nil)
        #expect(out[.rightWrist] == nil)
    }

    @Test func aJointLostLongerThanTheResetWindowRestartsAtItsNewPosition() {
        var s = PoseSmoother(resetAfter: 0.5)
        _ = s.smooth(NormalizedPose(timestamp: 0, points: [.leftWrist: PosePoint(x: 0.2, y: 0.5, confidence: 0.9)]))
        _ = s.smooth(NormalizedPose(timestamp: 0.5, points: [:]))
        let back = s.smooth(NormalizedPose(timestamp: 1.0, points: [.leftWrist: PosePoint(x: 0.7, y: 0.4, confidence: 0.9)]))
        #expect(back[.leftWrist]?.x == 0.7)
        #expect(back[.leftWrist]?.y == 0.4)
    }

    @Test func keepsTheTimestampAndAspect() {
        var s = PoseSmoother()
        let out = s.smooth(NormalizedPose(timestamp: 3, points: [:], imageAspect: 0.75))
        #expect(out.timestamp == 3)
        #expect(out.imageAspect == 0.75)
    }
}

@Suite("PoseMetrics")
struct PoseMetricsTests {
    @Test func distanceIsInFrameHeights() {
        let a = PosePoint(x: 0, y: 0, confidence: 1), b = PosePoint(x: 1, y: 0, confidence: 1)
        #expect(abs(PoseMetrics.distance(a, b, aspect: 0.75) - 0.75) < 1e-12)
        let c = PosePoint(x: 0, y: 1, confidence: 1)
        #expect(abs(PoseMetrics.distance(a, c, aspect: 0.75) - 1) < 1e-12)
    }

    @Test func wristSeparationIsRelativeToTheBody() {
        // Same ratio near and far from the camera.
        let near = MotionFixtures.chestPose(ratio: 2.0, at: 0, shoulderWidth: 0.2)
        let far = MotionFixtures.chestPose(ratio: 2.0, at: 0, shoulderWidth: 0.07)
        let r1 = PoseMetrics.wristSeparationRatio(near, minimumConfidence: 0.3)
        let r2 = PoseMetrics.wristSeparationRatio(far, minimumConfidence: 0.3)
        #expect(abs((r1 ?? 0) - 2) < 1e-9)
        #expect(abs((r2 ?? 0) - 2) < 1e-9)
    }

    @Test func gatedJointsGiveNoSignal() {
        let low = MotionFixtures.chestPose(ratio: 2, at: 0, confidence: 0.2)
        #expect(PoseMetrics.wristSeparationRatio(low, minimumConfidence: 0.3) == nil)
        let noWrists = MotionFixtures.chestPose(ratio: 2, at: 0, wrists: false)
        #expect(PoseMetrics.wristSeparationRatio(noWrists, minimumConfidence: 0.3) == nil)
        #expect(PoseMetrics.torsoLength(noWrists, minimumConfidence: 0.3) != nil)
    }
}

@Suite("PoseQualityEvaluator")
struct PoseQualityEvaluatorTests {
    private let evaluator = PoseQualityEvaluator()

    @Test func nobodyMeansFindingYou() {
        #expect(evaluator.evaluate(nil, region: .upperBody) == .findingYou)
        #expect(evaluator.evaluate(NormalizedPose(timestamp: 0, points: [:]), region: .upperBody) == .findingYou)
        let ghost = MotionFixtures.chestPose(ratio: 1, at: 0, confidence: 0.05)
        #expect(evaluator.evaluate(ghost, region: .upperBody) == .findingYou)
    }

    @Test func aWellPlacedUpperBodyIsGood() {
        #expect(evaluator.evaluate(MotionFixtures.chestPose(ratio: 0.6, at: 0), region: .upperBody) == .good)
    }

    @Test func hiddenHandsAskForTheUpperBody() {
        let pose = MotionFixtures.chestPose(ratio: 1, at: 0, wrists: false)
        #expect(evaluator.evaluate(pose, region: .upperBody) == .showUpperBody)
    }

    @Test func tooCloseOrCutByTheEdgeAsksToMoveBack() {
        let huge = MotionFixtures.chestPose(ratio: 0.6, at: 0, shoulderWidth: 0.3)
        #expect(evaluator.evaluate(huge, region: .upperBody) == .moveBack)
        let atEdge = MotionFixtures.chestPose(ratio: 6.9, at: 0)   // wrists at x ≈ 0.02 and 0.98
        #expect(evaluator.evaluate(atEdge, region: .upperBody) == .moveBack)
    }

    @Test func tooFarAsksToComeCloser() {
        let tiny = MotionFixtures.chestPose(ratio: 0.6, at: 0, shoulderWidth: 0.04)
        #expect(evaluator.evaluate(tiny, region: .upperBody) == .moveCloser)
    }

    @Test func fullBodyNeedsTheLegs() {
        let pose = MotionFixtures.chestPose(ratio: 0.6, at: 0)   // no knees or ankles
        #expect(evaluator.evaluate(pose, region: .fullBody) == .showFullBody)
    }
}
