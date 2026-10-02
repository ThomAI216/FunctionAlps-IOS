import Foundation

/// Where a motion session is, for the UI.
enum MotionSessionState: Equatable, Sendable {
    /// Not ready yet; the hint says what to change.
    case positioning(PositioningHint)
    /// Ready; staying still for a moment while the baseline is measured (0…1).
    case holdingStill(progress: Double)
    /// 3 · 2 · 1.
    case countdown(Int)
    /// Counting. `showsGo` for the first moment after the countdown.
    case active(reps: Int, showsGo: Bool)
    /// Counting paused: the detector's joints are not usable right now. Nothing counts meanwhile.
    case trackingLost(reps: Int)
    case completed(reps: Int)
}

/// One exercise from "finding you" to the result: positioning → hold still (calibration) → countdown →
/// counting → completed. Feeds every frame through the smoother, the positioning check and the
/// exercise's detector. Pure and synchronous — tests drive it with synthetic frames, no camera.
struct MotionSession: Sendable {
    struct Config: Equatable, Sendable {
        var prescribedReps: Int
        /// Continuous good positioning needed before the countdown (§20: ~0.5–1 s).
        var stableDuration: TimeInterval = 0.8
        var countdownSeconds = 3
        var goDuration: TimeInterval = 0.8
        /// Bad positioning frames tolerated this long before falling back (camera noise, a blink of the detector).
        var positioningGrace: TimeInterval = 0.4
        /// Unusable frames shown as "tracking lost" after this long (shorter gaps are invisible).
        var lostAfter: TimeInterval = 0.25
        /// Unusable this long → back to positioning; the reps already verified are kept.
        var resetAfter: TimeInterval = 2.5
        var trackingMode = "apple_vision_2d"
    }

    let config: Config
    private(set) var detector: any MovementDetector
    private(set) var state: MotionSessionState = .positioning(.findingYou)
    /// The last smoothed pose (the development skeleton draws it).
    private(set) var smoothedPose: NormalizedPose?
    private(set) var lastHint: PositioningHint = .findingYou

    private var smoother: PoseSmoother
    private let evaluator: PoseQualityEvaluator
    private var stableSince: TimeInterval?
    private var lastGoodAt: TimeInterval?
    private var countdownStartedAt: TimeInterval?
    private var goUntil: TimeInterval = 0
    private var calibrationPoses: [NormalizedPose] = []
    private var lostSince: TimeInterval?
    private var bankedReps = 0
    private var firstActiveAt: TimeInterval?
    private var endedAt: TimeInterval?
    private var countingFrames = 0
    private var reliableFrames = 0
    private var confidenceSum = 0.0

    init(detector: any MovementDetector, config: Config, evaluator: PoseQualityEvaluator = PoseQualityEvaluator()) {
        self.detector = detector
        self.config = config
        self.evaluator = evaluator
        smoother = PoseSmoother(profile: detector.smoothing, minimumConfidence: evaluator.minimumConfidence)
    }

    /// Verified repetitions, including those banked before a long tracking loss.
    var reps: Int { bankedReps + detector.reps }

    var isFinished: Bool {
        if case .completed = state { return true }
        return false
    }

    @discardableResult
    mutating func process(_ frame: PoseFrame) -> MotionSessionState {
        guard !isFinished else { return state }
        let pose = frame.pose.map { smoother.smooth($0) }
        smoothedPose = pose
        switch state {
        case .positioning, .holdingStill, .countdown: prepare(pose, at: frame.timestamp)
        case .active, .trackingLost: count(pose, at: frame.timestamp)
        case .completed: break
        }
        return state
    }

    /// The member stops before the target (or the screen closes): the session ends with what was verified.
    mutating func finish(at time: TimeInterval) {
        guard !isFinished else { return }
        endedAt = time
        state = .completed(reps: reps)
    }

    /// The structured result, once the session has ended. `date` maps a frame timestamp to wall-clock time.
    func result(date: (TimeInterval) -> Date) -> MotionSessionResult? {
        guard let endedAt else { return nil }
        let start = firstActiveAt ?? endedAt
        let coverage = countingFrames > 0 ? Double(reliableFrames) / Double(countingFrames) : 0
        let meanConfidence = reliableFrames > 0 ? confidenceSum / Double(reliableFrames) : 0
        let confidence = (min(max(coverage * meanConfidence, 0), 1) * 100).rounded() / 100
        return MotionSessionResult(
            exerciseId: detector.exerciseId,
            prescribedReps: config.prescribedReps,
            completedReps: reps,
            completed: reps >= config.prescribedReps,
            startedAt: date(start),
            endedAt: date(endedAt),
            durationSeconds: Int((endedAt - start).rounded()),
            trackingConfidence: confidence,
            trackingMode: config.trackingMode,
            detectorVersion: detector.detectorVersion
        )
    }

    // MARK: - Before counting

    private mutating func prepare(_ pose: NormalizedPose?, at time: TimeInterval) {
        let hint = evaluator.evaluate(pose, region: detector.region)
        lastHint = hint
        if hint == .good { lastGoodAt = time }
        let withinGrace = lastGoodAt.map { time - $0 <= config.positioningGrace } ?? false

        if hint != .good && !withinGrace {
            stableSince = nil
            countdownStartedAt = nil
            calibrationPoses = []
            state = .positioning(hint)
            return
        }

        if let start = countdownStartedAt {
            let elapsed = time - start
            if elapsed >= Double(config.countdownSeconds) {
                beginCounting(at: time)
            } else {
                state = .countdown(config.countdownSeconds - Int(elapsed))
            }
            return
        }

        // Holding still: only good frames feed the baseline.
        let since = stableSince ?? time
        stableSince = since
        if hint == .good, let pose { calibrationPoses.append(pose) }
        let held = time - since
        if held >= config.stableDuration {
            detector.calibrate(with: calibrationPoses)
            calibrationPoses = []
            countdownStartedAt = time
            state = .countdown(config.countdownSeconds)
        } else {
            state = .holdingStill(progress: held / config.stableDuration)
        }
    }

    private mutating func beginCounting(at time: TimeInterval) {
        countdownStartedAt = nil
        stableSince = nil
        if firstActiveAt == nil { firstActiveAt = time }
        goUntil = time + config.goDuration
        lostSince = nil
        state = .active(reps: reps, showsGo: true)
    }

    // MARK: - Counting

    private mutating func count(_ pose: NormalizedPose?, at time: TimeInterval) {
        countingFrames += 1
        // No person at all is fed as an empty pose, so the detector's run of confirming frames breaks too.
        let update = detector.process(pose ?? NormalizedPose(timestamp: time, points: [:]))

        if update == .trackingLost {
            let since = lostSince ?? time
            lostSince = since
            if time - since >= config.resetAfter {
                // Gone for good: keep what was verified, start positioning again from nothing.
                bankedReps += detector.reps
                detector.reset()
                smoother.reset()
                lostSince = nil
                lastGoodAt = nil
                stableSince = nil
                lastHint = .findingYou
                state = .positioning(.findingYou)
            } else if time - since >= config.lostAfter {
                state = .trackingLost(reps: reps)
            } else {
                state = .active(reps: reps, showsGo: time < goUntil)
            }
            return
        }

        lostSince = nil
        reliableFrames += 1
        if let pose { confidenceSum += PoseMetrics.meanConfidence(pose, joints: detector.requiredJoints) }
        if reps >= config.prescribedReps {
            endedAt = time
            state = .completed(reps: reps)
        } else {
            state = .active(reps: reps, showsGo: time < goUntil)
        }
    }
}
