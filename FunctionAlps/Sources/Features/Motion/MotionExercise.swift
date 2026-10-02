import Foundation

/// An exercise the camera can count, with its prescription. The catalog grows one detector at a time
/// (chest opener → squat to overhead → pogo jumps → calf raises, docs/MOTION_TRACKING.md §51).
struct MotionExercise: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case chestOpener = "chest_opener"
    }

    let kind: Kind
    let prescribedReps: Int

    static func chestOpener(reps: Int = 10) -> MotionExercise {
        MotionExercise(kind: .chestOpener, prescribedReps: reps)
    }

    var title: String {
        switch kind {
        case .chestOpener: String(localized: "motion.exercise.chestOpener", defaultValue: "Chest opener")
        }
    }

    /// One line on how to move, shown before and during counting.
    var how: String {
        switch kind {
        case .chestOpener: String(localized: "motion.exercise.chestOpener.how", defaultValue: "Open your arms wide, then bring them back in front of you.")
        }
    }

    func makeDetector() -> any MovementDetector {
        switch kind {
        case .chestOpener: ChestOpenerDetector()
        }
    }

    func makeSession(trackingMode: String) -> MotionSession {
        MotionSession(detector: makeDetector(), config: .init(prescribedReps: prescribedReps, trackingMode: trackingMode))
    }
}
