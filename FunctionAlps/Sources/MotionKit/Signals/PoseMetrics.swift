import Foundation

/// Body-relative geometry. Never rely on raw image distances: a member may stand 1.5 m or 3 m away, be
/// tall or short. Every signal is divided by one of the body's own lengths.
enum PoseMetrics {
    /// Euclidean distance in frame heights (x corrected by the frame's aspect ratio).
    static func distance(_ a: PosePoint, _ b: PosePoint, aspect: Double) -> Double {
        let dx = (a.x - b.x) * aspect
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func midpoint(_ a: PosePoint, _ b: PosePoint) -> PosePoint {
        PosePoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, confidence: min(a.confidence, b.confidence))
    }

    /// Shoulder-to-shoulder distance, frame heights.
    static func shoulderWidth(_ pose: NormalizedPose, minimumConfidence: Double) -> Double? {
        guard let l = pose.reliable(.leftShoulder, minimumConfidence: minimumConfidence),
              let r = pose.reliable(.rightShoulder, minimumConfidence: minimumConfidence) else { return nil }
        return distance(l, r, aspect: pose.imageAspect)
    }

    /// Hip-to-hip distance, frame heights.
    static func hipWidth(_ pose: NormalizedPose, minimumConfidence: Double) -> Double? {
        guard let l = pose.reliable(.leftHip, minimumConfidence: minimumConfidence),
              let r = pose.reliable(.rightHip, minimumConfidence: minimumConfidence) else { return nil }
        return distance(l, r, aspect: pose.imageAspect)
    }

    /// Shoulder midpoint to hip midpoint, frame heights.
    static func torsoLength(_ pose: NormalizedPose, minimumConfidence: Double) -> Double? {
        guard let ls = pose.reliable(.leftShoulder, minimumConfidence: minimumConfidence),
              let rs = pose.reliable(.rightShoulder, minimumConfidence: minimumConfidence),
              let lh = pose.reliable(.leftHip, minimumConfidence: minimumConfidence),
              let rh = pose.reliable(.rightHip, minimumConfidence: minimumConfidence) else { return nil }
        return distance(midpoint(ls, rs), midpoint(lh, rh), aspect: pose.imageAspect)
    }

    /// Below this a shoulder width is a detection collapse (member side-on, shoulders merged), not a scale.
    static let minimumScale = 0.02

    /// Wrist-to-wrist distance ÷ shoulder width: ≈0.3 hands together in front, ≈1 arms by the sides,
    /// ≥2 arms opened wide. Nil when either wrist or shoulder fails the confidence gate.
    static func wristSeparationRatio(_ pose: NormalizedPose, minimumConfidence: Double) -> Double? {
        guard let width = shoulderWidth(pose, minimumConfidence: minimumConfidence), width > minimumScale,
              let lw = pose.reliable(.leftWrist, minimumConfidence: minimumConfidence),
              let rw = pose.reliable(.rightWrist, minimumConfidence: minimumConfidence) else { return nil }
        return distance(lw, rw, aspect: pose.imageAspect) / width
    }

    /// Mean confidence over `joints` (missing joints count as 0).
    static func meanConfidence(_ pose: NormalizedPose, joints: Set<BodyJoint>) -> Double {
        guard !joints.isEmpty else { return 0 }
        return joints.reduce(0) { $0 + (pose[$1]?.confidence ?? 0) } / Double(joints.count)
    }
}
