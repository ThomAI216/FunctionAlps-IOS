import Foundation

/// One 1€ filter per coordinate of every joint. A joint that fails the confidence gate is left out of
/// the output (never interpolated); when it has been missing longer than `resetAfter`, its filters
/// restart so the reacquired position is not dragged from where it was lost.
struct PoseSmoother: Sendable {
    var profile: SmoothingProfile
    var minimumConfidence: Double
    var resetAfter: TimeInterval

    private var filters: [BodyJoint: (x: OneEuroFilter, y: OneEuroFilter)] = [:]
    private var lastSeen: [BodyJoint: TimeInterval] = [:]

    init(profile: SmoothingProfile = .slow, minimumConfidence: Double = 0.3, resetAfter: TimeInterval = 0.5) {
        self.profile = profile
        self.minimumConfidence = minimumConfidence
        self.resetAfter = resetAfter
    }

    mutating func smooth(_ pose: NormalizedPose) -> NormalizedPose {
        var out: [BodyJoint: PosePoint] = [:]
        for (joint, point) in pose.points where point.confidence >= minimumConfidence {
            if let seen = lastSeen[joint], pose.timestamp - seen > resetAfter { filters[joint] = nil }
            var pair = filters[joint] ?? (
                OneEuroFilter(minCutoff: profile.minCutoff, beta: profile.beta, derivativeCutoff: profile.derivativeCutoff),
                OneEuroFilter(minCutoff: profile.minCutoff, beta: profile.beta, derivativeCutoff: profile.derivativeCutoff)
            )
            let x = pair.x.filter(point.x, at: pose.timestamp)
            let y = pair.y.filter(point.y, at: pose.timestamp)
            filters[joint] = pair
            lastSeen[joint] = pose.timestamp
            out[joint] = PosePoint(x: x, y: y, confidence: point.confidence)
        }
        return NormalizedPose(timestamp: pose.timestamp, points: out, imageAspect: pose.imageAspect)
    }

    mutating func reset() {
        filters = [:]
        lastSeen = [:]
    }
}
