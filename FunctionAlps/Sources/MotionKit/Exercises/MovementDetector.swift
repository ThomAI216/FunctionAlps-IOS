import Foundation

/// What the motion pipeline tells the UI. Detectors emit `.tracking`, `.rep`, `.hold` and
/// `.trackingLost`; `MotionSession` adds the rest. The UI never needs an exercise's rules.
enum MovementUpdate: Equatable, Sendable {
    case waiting
    case positioning(PositioningHint)
    case tracking(reps: Int)
    /// A repetition was just counted; the detector's running total.
    case rep(Int)
    case hold(TimeInterval)
    case completed
    /// The joints this detector needs failed the confidence gate in this frame.
    case trackingLost
}

/// A detector's live signal, for the development overlay.
struct DetectorReadout: Equatable, Sendable {
    let signalName: String
    let value: Double?
    let enterThreshold: Double
    let exitThreshold: Double
    let phase: String
}

/// One exercise's movement signature as code: which joints, which signal, which state machine.
/// Consumes `NormalizedPose` only — a detector must never import Vision (or any pose engine), so every
/// rule is unit-testable with synthetic poses and the engine can be swapped underneath.
protocol MovementDetector: Sendable {
    /// Matches the exercise library id (e.g. `chest_opener`).
    var exerciseId: String { get }
    /// Saved with every result, because thresholds change over time (e.g. `chest_opener_v1.0`).
    var detectorVersion: String { get }
    var region: BodyRegion { get }
    var cameraView: CameraViewRequirement { get }
    var requiredJoints: Set<BodyJoint> { get }
    var smoothing: SmoothingProfile { get }
    /// Repetitions counted since the last `reset()`.
    var reps: Int { get }
    var readout: DetectorReadout { get }

    /// The quiet-standing poses collected before the countdown (§21 dynamic calibration). Subtle
    /// movements derive their thresholds from the noise seen here; large ones may ignore it.
    mutating func calibrate(with poses: [NormalizedPose])
    mutating func process(_ pose: NormalizedPose) -> MovementUpdate
    /// Back to the initial state, count included.
    mutating func reset()
}

extension MovementDetector {
    mutating func calibrate(with poses: [NormalizedPose]) {}
}
