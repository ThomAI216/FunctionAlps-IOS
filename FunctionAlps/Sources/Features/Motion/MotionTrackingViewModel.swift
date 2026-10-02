@preconcurrency import AVFoundation
import Foundation
import Observation
import QuartzCore
import UIKit

/// One camera-counted exercise: camera permission, the camera itself, and the `MotionSession` that turns
/// its pose frames into repetitions. Nothing is uploaded or stored: the session ends with a
/// `MotionSessionResult` in memory (saving it to `movement_sessions` is the next slice).
@MainActor
@Observable
final class MotionTrackingViewModel {
    enum CameraState: Equatable {
        case idle, starting, running
        /// Camera permission denied or restricted.
        case unauthorized
        /// No camera (the simulator).
        case unavailable
        case failed
    }

    let exercise: MotionExercise
    private(set) var camera: CameraState = .idle
    private(set) var state: MotionSessionState = .positioning(.findingYou)
    private(set) var reps = 0
    /// The smoothed pose of the last frame (the development skeleton).
    private(set) var pose: NormalizedPose?
    private(set) var readout: DetectorReadout?
    private(set) var result: MotionSessionResult?
    private(set) var framesPerSecond = 0.0
    private(set) var usesFrontCamera = true

    @ObservationIgnored private let sensor: MotionCamera
    @ObservationIgnored private var session: MotionSession
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var frameTimes: [TimeInterval] = []
    /// False once the screen has left (or the app went to the background): a start still awaiting the
    /// permission prompt or the camera must not leave the camera running behind it.
    @ObservationIgnored private var wanted = false

    init(exercise: MotionExercise) {
        self.exercise = exercise
        let sensor = MotionCamera()
        self.sensor = sensor
        session = exercise.makeSession(trackingMode: sensor.engine)
    }

    var captureSession: AVCaptureSession { sensor.session }
    var region: BodyRegion { session.detector.region }

    func start() async {
        guard result == nil, camera != .starting, camera != .running else { return }
        wanted = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                camera = .unauthorized
                return
            }
        default:
            camera = .unauthorized
            return
        }

        camera = .starting
        do {
            try await sensor.start(position: usesFrontCamera ? .front : .back)
        } catch MotionCamera.Failure.unavailable {
            camera = .unavailable
            return
        } catch {
            Log.app.error("motion camera failed to start: \(String(describing: error), privacy: .public)")
            camera = .failed
            return
        }
        guard wanted else {
            sensor.stop()
            return
        }
        camera = .running
        UIApplication.shared.isIdleTimerDisabled = true
        reader?.cancel()
        let frames = sensor.makeFrameStream()
        reader = Task { [weak self] in
            for await frame in frames {
                guard let self else { return }
                self.handle(frame)
            }
        }
    }

    /// Leaves the screen: camera off, nothing kept.
    func stop() {
        wanted = false
        reader?.cancel()
        reader = nil
        sensor.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        if camera == .running || camera == .starting { camera = .idle }
    }

    /// The member stops before the target: the result keeps what was verified.
    func finish() {
        guard result == nil else { return }
        session.finish(at: CACurrentMediaTime())
        state = session.state
        complete()
    }

    /// A fresh session (after a result, or after switching camera).
    func restart() async {
        session = exercise.makeSession(trackingMode: sensor.engine)
        result = nil
        reps = 0
        pose = nil
        readout = nil
        state = session.state
        await start()
    }

    func switchCamera() async {
        usesFrontCamera.toggle()
        if camera == .running { camera = .idle }
        await restart()
    }

    private func handle(_ frame: PoseFrame) {
        guard wanted, result == nil else { return }
        let before = session.reps
        state = session.process(frame)
        pose = session.smoothedPose
        readout = session.detector.readout
        reps = session.reps
        measureRate(frame.timestamp)
        if reps > before {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIAccessibility.post(notification: .announcement, argument: Self.countLabel(reps, of: exercise.prescribedReps))
        }
        if session.isFinished { complete() }
    }

    private func complete() {
        result = session.result(date: Self.wallClock)
        // The brief's rule: the camera closes the moment the exercise is done.
        sensor.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        camera = .idle
        if result?.completed == true { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func measureRate(_ time: TimeInterval) {
        frameTimes.append(time)
        frameTimes.removeAll { time - $0 > 1 }
        framesPerSecond = Double(frameTimes.count)
    }

    /// Frame timestamps are host-clock seconds (`CACurrentMediaTime`); this maps one to wall-clock time.
    nonisolated private static func wallClock(_ time: TimeInterval) -> Date {
        Date(timeIntervalSinceNow: time - CACurrentMediaTime())
    }

    nonisolated static func countLabel(_ reps: Int, of target: Int) -> String {
        String(localized: "motion.count.a11y", defaultValue: "\(reps) of \(target) repetitions")
    }
}
