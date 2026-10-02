import Foundation

/// What the member should do so the camera can see the exercise. The UI turns it into one short line.
enum PositioningHint: String, Equatable, Sendable {
    /// Nobody in the frame yet.
    case findingYou
    /// Shoulders, arms or hands are not all visible.
    case showUpperBody
    /// Some of shoulders, hips, knees, ankles are not visible.
    case showFullBody
    /// Too close: the body is too large or touches the frame's edge.
    case moveBack
    /// Too far: the body is too small to track reliably.
    case moveCloser
    /// Ready.
    case good
}

/// Decides whether a pose is good enough to start (and keep) counting: a person is there, the required
/// joints pass the confidence gate, nothing is cut by the frame edge, the body is neither tiny nor huge.
struct PoseQualityEvaluator: Equatable, Sendable {
    var minimumConfidence = 0.3
    /// Fraction of the frame a required joint must stay away from each edge.
    var edgeMargin = 0.03
    /// Shoulder width in frame heights: below this the member is too far away for a stable signal.
    var minimumShoulderWidth = 0.06
    /// Above this the member is too close: arms opened wide would leave a portrait frame.
    var maximumShoulderWidth = 0.22

    func evaluate(_ pose: NormalizedPose?, region: BodyRegion) -> PositioningHint {
        guard let pose, pose.points.values.contains(where: { $0.confidence >= minimumConfidence }) else {
            return .findingYou
        }
        let required = region.requiredJoints
        let visible = required.compactMap { pose.reliable($0, minimumConfidence: minimumConfidence) }
        let lo = edgeMargin, hi = 1 - edgeMargin
        let touchesEdge = visible.contains { $0.x < lo || $0.x > hi || $0.y < lo || $0.y > hi }
        let width = PoseMetrics.shoulderWidth(pose, minimumConfidence: minimumConfidence)

        if let width, width > maximumShoulderWidth { return .moveBack }
        if touchesEdge { return .moveBack }
        if visible.count < required.count {
            // A large body with joints missing is usually too close; a small one is out of frame or hidden.
            if let width, width > maximumShoulderWidth * 0.7 { return .moveBack }
            return region == .upperBody ? .showUpperBody : .showFullBody
        }
        if let width, width < minimumShoulderWidth { return .moveCloser }
        return .good
    }
}
