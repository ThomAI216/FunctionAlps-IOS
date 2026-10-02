import Foundation
@testable import FunctionAlps

/// Synthetic poses for the motion tests: a member facing the camera, shoulders 0.14 frame heights apart,
/// at 30 frames per second. No camera, no Vision.
enum MotionFixtures {
    static let fps = 30.0
    static let shoulderY = 0.35
    static let shoulderWidth = 0.14
    static let centerX = 0.5

    /// A pose whose wrist separation is `ratio` shoulder widths.
    static func chestPose(ratio: Double, at time: TimeInterval, confidence: Double = 0.9, wrists: Bool = true,
                          shoulderWidth: Double = MotionFixtures.shoulderWidth) -> NormalizedPose {
        let half = shoulderWidth / 2
        var points: [BodyJoint: PosePoint] = [
            .leftShoulder: PosePoint(x: centerX - half, y: shoulderY, confidence: confidence),
            .rightShoulder: PosePoint(x: centerX + half, y: shoulderY, confidence: confidence),
            .leftElbow: PosePoint(x: centerX - half - 0.03, y: shoulderY + 0.12, confidence: confidence),
            .rightElbow: PosePoint(x: centerX + half + 0.03, y: shoulderY + 0.12, confidence: confidence),
            .neck: PosePoint(x: centerX, y: shoulderY - 0.02, confidence: confidence),
            .leftHip: PosePoint(x: centerX - half * 0.8, y: shoulderY + 0.3, confidence: confidence),
            .rightHip: PosePoint(x: centerX + half * 0.8, y: shoulderY + 0.3, confidence: confidence),
        ]
        if wrists {
            let w = ratio * shoulderWidth / 2
            points[.leftWrist] = PosePoint(x: centerX - w, y: shoulderY + 0.05, confidence: confidence)
            points[.rightWrist] = PosePoint(x: centerX + w, y: shoulderY + 0.05, confidence: confidence)
        }
        return NormalizedPose(timestamp: time, points: points)
    }

    /// One frame per entry of `ratios`, starting at `start`. A nil ratio is a frame without wrists.
    static func frames(_ ratios: [Double?], start: TimeInterval = 0) -> [NormalizedPose] {
        ratios.enumerated().map { i, ratio in
            chestPose(ratio: ratio ?? 1, at: start + Double(i) / fps, wrists: ratio != nil)
        }
    }

    /// `count` frames holding `ratio`.
    static func hold(_ ratio: Double?, _ count: Int) -> [Double?] { Array(repeating: ratio, count: count) }

    /// A smooth closed → open → closed cycle over `seconds`.
    static func cycle(closed: Double = 0.6, open: Double = 2.6, seconds: Double = 2) -> [Double?] {
        let n = Int(seconds * fps)
        return (0..<n).map { i in
            let phase = Double(i) / Double(n)
            return closed + (open - closed) * (1 - cos(2 * Double.pi * phase)) / 2
        }
    }
}
