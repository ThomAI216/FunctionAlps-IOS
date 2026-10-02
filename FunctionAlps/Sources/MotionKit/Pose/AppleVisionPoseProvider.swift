import CoreVideo
import Foundation
import ImageIO
import Vision

/// A pose engine: one camera frame in, one engine-independent pose out (nil = nobody found).
/// Called synchronously on the camera's video queue; the frame is only read, never kept.
protocol PoseProvider {
    /// Saved with results as `tracking_mode` (e.g. `apple_vision_2d`).
    var engine: String { get }
    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, timestamp: TimeInterval) throws -> NormalizedPose?
}

/// Apple Vision's 2D body pose (`VNDetectHumanBodyPoseRequest`): on-device, no model download, 19 points.
/// Not thread-safe by design — the camera owns one and uses it from its video queue only.
final class AppleVisionPoseProvider: PoseProvider {
    let engine = "apple_vision_2d"
    private let request = VNDetectHumanBodyPoseRequest()

    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, timestamp: TimeInterval) throws -> NormalizedPose? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([request])
        guard let observations = request.results, !observations.isEmpty else { return nil }

        // Several people: follow the largest (nearest) one.
        let candidates = observations.compactMap { observation -> [BodyJoint: PosePoint]? in
            guard let recognized = try? observation.recognizedPoints(.all) else { return nil }
            let points = Self.convert(recognized)
            return points.isEmpty ? nil : points
        }
        guard let person = candidates.max(by: { Self.extent($0) < Self.extent($1) }) else { return nil }

        var width = Double(CVPixelBufferGetWidth(pixelBuffer))
        var height = Double(CVPixelBufferGetHeight(pixelBuffer))
        if [.left, .right, .leftMirrored, .rightMirrored].contains(orientation) { swap(&width, &height) }
        return NormalizedPose(timestamp: timestamp, points: person, imageAspect: height > 0 ? width / height : 1)
    }

    /// Vision's points are normalised with the origin bottom-left; ours are top-left (y down).
    private static func convert(_ recognized: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> [BodyJoint: PosePoint] {
        let names: [(VNHumanBodyPoseObservation.JointName, BodyJoint)] = [
            (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye), (.leftEar, .leftEar), (.rightEar, .rightEar),
            (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
            (.leftHip, .leftHip), (.rightHip, .rightHip), (.root, .root),
            (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
        ]
        var out: [BodyJoint: PosePoint] = [:]
        for (name, joint) in names {
            guard let p = recognized[name], p.confidence > 0 else { continue }
            out[joint] = PosePoint(x: Double(p.location.x), y: 1 - Double(p.location.y), confidence: Double(p.confidence))
        }
        return out
    }

    /// Area of the box around a person's confident points — how much of the frame they fill.
    private static func extent(_ points: [BodyJoint: PosePoint]) -> Double {
        let sure = points.values.filter { $0.confidence >= 0.3 }
        guard let minX = sure.map(\.x).min(), let maxX = sure.map(\.x).max(),
              let minY = sure.map(\.y).min(), let maxY = sure.map(\.y).max() else { return 0 }
        return (maxX - minX) * (maxY - minY)
    }
}
