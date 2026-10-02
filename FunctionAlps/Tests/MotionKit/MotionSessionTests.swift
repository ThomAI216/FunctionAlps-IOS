import Foundation
import Testing
@testable import FunctionAlps

@Suite("MotionSession")
struct MotionSessionTests {
    private typealias F = MotionFixtures

    /// Feeds frames at 30 fps on one continuous clock and remembers every state the session went through.
    private struct Feeder {
        var session: MotionSession
        var time: TimeInterval = 0
        var states: [MotionSessionState] = []

        init(reps: Int = 3) {
            session = MotionSession(detector: ChestOpenerDetector(), config: .init(prescribedReps: reps))
        }

        mutating func feed(_ ratios: [Double?]) {
            for ratio in ratios {
                let pose = ratio.map { F.chestPose(ratio: $0, at: time) }
                states.append(session.process(PoseFrame(timestamp: time, pose: pose)))
                time += 1 / F.fps
            }
        }

        /// Nobody in the frame for `count` frames.
        mutating func empty(_ count: Int) {
            for _ in 0..<count {
                states.append(session.process(PoseFrame(timestamp: time, pose: nil)))
                time += 1 / F.fps
            }
        }

        /// Stand still long enough to pass positioning, hold-still and the countdown.
        mutating func getReady() {
            feed(F.hold(0.6, Int((0.8 + 3 + 0.2) * F.fps)))
        }
    }

    @Test func nobodyInTheFrameIsFindingYou() {
        var f = Feeder()
        f.empty(10)
        #expect(f.session.state == .positioning(.findingYou))
    }

    @Test func positioningThenHoldStillThenCountdownThenGo() {
        var f = Feeder()
        f.getReady()
        #expect(f.states.contains { if case .holdingStill = $0 { true } else { false } })
        #expect(f.states.contains(.countdown(3)))
        #expect(f.states.contains(.countdown(2)))
        #expect(f.states.contains(.countdown(1)))
        #expect(f.states.contains(.active(reps: 0, showsGo: true)))
        // Countdown order: 3 before 2 before 1 before GO.
        let i3 = f.states.firstIndex(of: .countdown(3)), i1 = f.states.firstIndex(of: .countdown(1))
        let go = f.states.firstIndex(of: .active(reps: 0, showsGo: true))
        #expect(i3! < i1! && i1! < go!)
    }

    @Test func nothingCountsBeforeGo() {
        var f = Feeder()
        // Opening and closing the arms during positioning and the countdown: not counted.
        f.feed(F.cycle() + F.cycle())
        #expect(f.session.reps == 0)
    }

    @Test func countsToTheTargetAndCompletesWithAResult() throws {
        var f = Feeder(reps: 3)
        f.getReady()
        f.feed(F.cycle() + F.cycle() + F.cycle() + F.hold(0.6, 10))
        #expect(f.session.state == .completed(reps: 3))

        let origin = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try #require(f.session.result { origin.addingTimeInterval($0) })
        #expect(result.exerciseId == "chest_opener")
        #expect(result.prescribedReps == 3)
        #expect(result.completedReps == 3)
        #expect(result.completed)
        #expect(result.detectorVersion == "chest_opener_v1.0")
        #expect(result.trackingMode == "apple_vision_2d")
        #expect(result.durationSeconds >= 5 && result.durationSeconds <= 7)
        #expect(result.endedAt > result.startedAt)
        #expect(result.trackingConfidence > 0.85 && result.trackingConfidence <= 0.9)
    }

    @Test func framesAfterCompletionChangeNothing() {
        var f = Feeder(reps: 1)
        f.getReady()
        f.feed(F.cycle() + F.hold(0.6, 5))
        #expect(f.session.state == .completed(reps: 1))
        f.feed(F.cycle() + F.cycle())
        #expect(f.session.state == .completed(reps: 1))
    }

    @Test func trackingLossPausesAndAddsNoReps() {
        var f = Feeder(reps: 5)
        f.getReady()
        f.feed(F.cycle())
        #expect(f.session.reps == 1)
        f.feed(F.hold(2.6, 10))
        f.feed(F.hold(nil, 20))   // hands out of view for 0.67 s
        #expect(f.session.state == .trackingLost(reps: 1))
        f.feed(F.hold(0.6, 20))
        #expect(f.session.reps == 1)
        #expect(f.session.state == .active(reps: 1, showsGo: false))
    }

    @Test func aLongLossGoesBackToPositioningAndKeepsTheVerifiedReps() {
        var f = Feeder(reps: 3)
        f.getReady()
        f.feed(F.cycle() + F.cycle())
        #expect(f.session.reps == 2)
        f.empty(Int(3 * F.fps))   // walked away
        #expect(f.session.state == .positioning(.findingYou))
        #expect(f.session.reps == 2)

        f.getReady()
        f.feed(F.cycle() + F.hold(0.6, 5))
        #expect(f.session.state == .completed(reps: 3))
    }

    @Test func leavingDuringTheCountdownStartsPositioningAgain() {
        var f = Feeder()
        f.feed(F.hold(0.6, Int(1.5 * F.fps)))   // into the countdown
        #expect(f.states.contains(.countdown(3)))
        f.empty(20)
        #expect(f.session.state == .positioning(.findingYou))
    }

    @Test func aBlinkOfBadPositioningDoesNotRestartTheCountdown() {
        var f = Feeder()
        f.feed(F.hold(0.6, Int(1.5 * F.fps)))
        f.empty(3)   // 0.1 s, inside the grace
        f.feed(F.hold(0.6, 3))
        if case .countdown = f.session.state {} else { Issue.record("expected the countdown, got \(f.session.state)") }
    }

    @Test func finishingEarlyKeepsWhatWasVerified() throws {
        var f = Feeder(reps: 10)
        f.getReady()
        f.feed(F.cycle() + F.cycle())
        f.session.finish(at: f.time)
        #expect(f.session.state == .completed(reps: 2))
        let result = try #require(f.session.result { Date(timeIntervalSince1970: $0) })
        #expect(result.completedReps == 2)
        #expect(result.completed == false)
    }

    @Test func noResultBeforeTheSessionEnds() {
        var f = Feeder()
        f.getReady()
        #expect(f.session.result { Date(timeIntervalSince1970: $0) } == nil)
    }

    @Test func theResultEncodesToTheMovementSessionColumns() throws {
        let result = MotionSessionResult(
            exerciseId: "chest_opener", prescribedReps: 10, completedReps: 10, completed: true,
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 24), durationSeconds: 24,
            trackingConfidence: 0.92, trackingMode: "apple_vision_2d", detectorVersion: "chest_opener_v1.0"
        )
        let data = try JSONEncoder().encode(result)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == [
            "exercise_id", "prescribed_reps", "completed_reps", "completed", "started_at", "ended_at",
            "duration_seconds", "tracking_confidence", "tracking_mode", "detector_version",
        ])
        #expect(try JSONDecoder().decode(MotionSessionResult.self, from: data) == result)
    }
}
