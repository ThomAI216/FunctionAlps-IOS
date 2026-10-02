@preconcurrency import AVFoundation
import Foundation

/// The camera as a temporary movement sensor. Frames arrive on a private video queue, go through the
/// pose engine there (never on the main thread) and are released as soon as `captureOutput` returns:
/// only the extracted `PoseFrame` leaves this class. There is no photo output, no movie output and no
/// file anywhere — nothing a frame could be written to or uploaded from.
///
/// Thread-safety: `session` and `output` are touched only on `sessionQueue`, the pose provider only on
/// `videoQueue`, the current frame continuation only under `lock`. Hence `@unchecked Sendable`.
final class MotionCamera: NSObject, @unchecked Sendable {
    enum Failure: Error, Equatable {
        /// No camera on this device (the simulator) or for this position.
        case unavailable
        /// The capture session refused the input or output.
        case configuration
    }

    /// Bound to the on-screen preview (a preview layer shows frames; it stores none).
    let session = AVCaptureSession()
    var engine: String { provider.engine }

    private let lock = NSLock()
    private var continuation: AsyncStream<PoseFrame>.Continuation?
    private let output = AVCaptureVideoDataOutput()
    private let provider: any PoseProvider
    private let sessionQueue = DispatchQueue(label: "ch.functionalps.motion.session")
    private let videoQueue = DispatchQueue(label: "ch.functionalps.motion.video", qos: .userInitiated)

    init(provider: any PoseProvider = AppleVisionPoseProvider()) {
        self.provider = provider
        super.init()
    }

    deinit {
        continuation?.finish()
    }

    /// A fresh stream of processed frames (the previous one, if any, ends). One stream per start, because
    /// an `AsyncStream` whose reader is cancelled is finished for good. Only the newest frames are kept
    /// when the reader falls behind.
    func makeFrameStream() -> AsyncStream<PoseFrame> {
        let (stream, continuation) = AsyncStream.makeStream(of: PoseFrame.self, bufferingPolicy: .bufferingNewest(2))
        lock.withLock {
            self.continuation?.finish()
            self.continuation = continuation
        }
        return stream
    }

    /// Configures the camera at `position` and starts it. Throws `Failure` when there is no usable camera.
    func start(position: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
            sessionQueue.async { [self] in
                do {
                    try configure(position: position)
                    if !session.isRunning { session.startRunning() }
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    /// Stops the camera (the green indicator goes off) and ends the frame stream. Safe to call more than once.
    func stop() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure(position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw Failure.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for existing in session.inputs { session.removeInput(existing) }
        // Body pose needs no more than VGA; fewer pixels = cooler phone, longer battery.
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        guard session.canAddInput(input) else { throw Failure.configuration }
        session.addInput(input)

        if !session.outputs.contains(output) {
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(output) else { throw Failure.configuration }
            session.addOutput(output)
        }
        // Upright, un-mirrored buffers: Vision sees the member as they are, so "left" is their left.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }
}

extension MotionCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Host-clock seconds, the same clock as `CACurrentMediaTime()`.
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard let continuation = lock.withLock({ self.continuation }) else { return }
        let pose = try? provider.detect(in: pixelBuffer, orientation: .up, timestamp: time)
        continuation.yield(PoseFrame(timestamp: time, pose: pose))
    }
}
