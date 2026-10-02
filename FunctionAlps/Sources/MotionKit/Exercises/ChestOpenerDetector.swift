import Foundation

/// Chest opener: arms from closed (hands together in front, or by the sides) to wide open and back.
/// Signal = wrist separation ÷ shoulder width. CLOSED below `closedRatio`, OPEN above `openRatio`;
/// the gap between them is the hysteresis. Any arm shape counts — no shoulder angle is demanded.
struct ChestOpenerDetector: MovementDetector {
    static let id = "chest_opener"
    static let version = "chest_opener_v1.0"

    let exerciseId = Self.id
    let detectorVersion = Self.version
    let region = BodyRegion.upperBody
    let cameraView = CameraViewRequirement.front
    let requiredJoints: Set<BodyJoint> = [.leftWrist, .rightWrist, .leftShoulder, .rightShoulder]
    let smoothing = SmoothingProfile.slow
    var minimumConfidence = 0.3

    private var counter: TwoPhaseRepCounter
    private(set) var lastRatio: Double?

    init(openRatio: Double = 1.8, closedRatio: Double = 1.25, confirmFrames: Int = 3,
         minimumRepInterval: TimeInterval = 0.8, maximumOpenDuration: TimeInterval = 15) {
        counter = TwoPhaseRepCounter(config: .init(
            enterActive: openRatio, exitActive: closedRatio, activeIsHigh: true, confirmFrames: confirmFrames,
            minimumRepInterval: minimumRepInterval, maximumActiveDuration: maximumOpenDuration
        ))
    }

    var reps: Int { counter.reps }

    var readout: DetectorReadout {
        DetectorReadout(signalName: "wrist ÷ shoulder", value: lastRatio,
                        enterThreshold: counter.config.enterActive, exitThreshold: counter.config.exitActive,
                        phase: counter.phase == .active ? "open" : counter.phase == .neutral ? "closed" : "—")
    }

    mutating func process(_ pose: NormalizedPose) -> MovementUpdate {
        guard let ratio = PoseMetrics.wristSeparationRatio(pose, minimumConfidence: minimumConfidence) else {
            lastRatio = nil
            counter.markUnreliable()
            return .trackingLost
        }
        lastRatio = ratio
        return counter.process(ratio, at: pose.timestamp) ? .rep(counter.reps) : .tracking(reps: counter.reps)
    }

    mutating func reset() {
        counter.reset()
        lastRatio = nil
    }
}
