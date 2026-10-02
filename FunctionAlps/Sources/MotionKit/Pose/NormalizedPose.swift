import Foundation

// FunctionMotionKit — the camera as a temporary movement sensor (docs/MOTION_TRACKING.md).
// Everything under Pose/ (except AppleVisionPoseProvider), Filtering/, Signals/, Exercises/ and
// Session/ is Foundation-only: no Vision, no AVFoundation, no UIKit. Detectors consume this file's
// types and never know which pose engine produced them — the seam for MediaPipe later.

/// One body landmark: normalised image coordinates of the upright frame (origin top-left, x right,
/// y down, both 0…1) and the engine's confidence 0…1.
struct PosePoint: Equatable, Sendable {
    var x: Double
    var y: Double
    var confidence: Double
}

/// The joints FunctionMotionKit understands — Apple Vision's 19 body points. A MediaPipe provider
/// maps its 33 landmarks onto these (and may add foot points later without touching detectors).
enum BodyJoint: String, CaseIterable, Hashable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar, neck
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case leftHip, rightHip, root, leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// One person's pose in one frame, independent of the engine that found it.
struct NormalizedPose: Equatable, Sendable {
    let timestamp: TimeInterval
    let points: [BodyJoint: PosePoint]
    /// Width ÷ height of the frame the points were found in. Normalised x and y are fractions of
    /// different pixel lengths; distances multiply x by this so both axes share one unit (frame heights).
    var imageAspect: Double = 1

    subscript(_ joint: BodyJoint) -> PosePoint? { points[joint] }

    /// The point only when the engine is at least `minimumConfidence` sure of it. Missing positions are
    /// never invented: a gated-out joint is simply absent.
    func reliable(_ joint: BodyJoint, minimumConfidence: Double) -> PosePoint? {
        guard let p = points[joint], p.confidence >= minimumConfidence else { return nil }
        return p
    }

    /// True when every joint in `joints` passes the confidence gate.
    func hasReliable(_ joints: Set<BodyJoint>, minimumConfidence: Double) -> Bool {
        joints.allSatisfy { reliable($0, minimumConfidence: minimumConfidence) != nil }
    }
}

/// What the camera produced for one frame: a pose, or nobody (`pose == nil`).
struct PoseFrame: Sendable {
    let timestamp: TimeInterval
    let pose: NormalizedPose?
}

/// The part of the body an exercise needs in the frame.
enum BodyRegion: String, Sendable {
    /// Shoulders, elbows and wrists (arm movements).
    case upperBody
    /// Head to ankles (jumps, squats, calf raises).
    case fullBody

    var requiredJoints: Set<BodyJoint> {
        switch self {
        case .upperBody: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
        case .fullBody: [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        }
    }
}

/// How the member should face the phone for an exercise.
enum CameraViewRequirement: String, Sendable {
    case front, side, either
}
