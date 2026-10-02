import Foundation

/// The only thing a motion session leaves behind: a small structured record. No frame, photo, video or
/// face crop is ever part of it (docs/MOTION_TRACKING.md §19). Keys match the planned
/// `movement_sessions` columns.
struct MotionSessionResult: Equatable, Sendable, Codable {
    let exerciseId: String
    let prescribedReps: Int
    /// Repetitions the detector verified.
    let completedReps: Int
    /// True when `completedReps` reached `prescribedReps`.
    let completed: Bool
    /// "GO": the first moment repetitions could count.
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    /// How sure we are the camera reliably SAW the exercise (0…1): share of counting frames in which the
    /// detector's joints were usable × their mean confidence. Not a movement-quality score.
    let trackingConfidence: Double
    /// The pose engine (e.g. `apple_vision_2d`).
    let trackingMode: String
    /// The detector's version (e.g. `chest_opener_v1.0`), so old results stay interpretable.
    let detectorVersion: String

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case prescribedReps = "prescribed_reps"
        case completedReps = "completed_reps"
        case completed
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case trackingConfidence = "tracking_confidence"
        case trackingMode = "tracking_mode"
        case detectorVersion = "detector_version"
    }
}
