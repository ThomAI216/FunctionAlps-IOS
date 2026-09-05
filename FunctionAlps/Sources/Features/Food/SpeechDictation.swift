import AVFoundation
import Foundation
import Observation

/// "Describe by voice", the Expo `useWhisperMic` state machine: idle → recording → transcribing → idle.
/// Tap: the phone records a short AAC clip; tap again: the clip goes to `transcribe-audio` (the
/// sovereign Whisper) and the words land in the describe field like a typed meal. No language is sent,
/// so Whisper detects it — a member may speak French today and English tomorrow.
///
/// Plain `AVAudioRecorder`, deliberately NOT an `AVAudioEngine` tap: a tap installed on an input node
/// whose format is not yet valid raises an Objective-C exception Swift cannot catch, which is a hard
/// quit — the crash the owner saw on build 22.
@MainActor
@Observable
final class SpeechDictation: NSObject {
    private(set) var listening = false
    private(set) var transcribing = false
    private(set) var error: String?
    /// The finished transcript, delivered once per recording.
    var onFinal: ((String) -> Void)?

    private let transcribe: @Sendable (Data, String) async throws -> String
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    /// Recording stops itself after this long — a forgotten mic must not run for an hour.
    static let maxSeconds: TimeInterval = 90

    init(transcribe: @escaping @Sendable (Data, String) async throws -> String) {
        self.transcribe = transcribe
    }

    static var isAvailable: Bool { true }

    func toggle() {
        if transcribing { return }
        if listening { Task { await stopAndTranscribe() } } else { Task { await start() } }
    }

    private func start() async {
        error = nil
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            error = String(localized: "food.voice.micDenied", defaultValue: "The microphone isn't allowed. You can enable it in Settings, or type your meal below.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("meal-\(UUID().uuidString).m4a")
            // AAC mono at 16 kHz: what Whisper wants, and ~200 KB per minute in the JSON body.
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            guard rec.record(forDuration: Self.maxSeconds) else { throw CocoaError(.fileWriteUnknown) }
            recorder = rec
            fileURL = url
            listening = true
        } catch {
            Log.data.error("voice.start: \(String(describing: error), privacy: .public)")
            self.error = String(localized: "food.voice.failed", defaultValue: "Couldn't start listening · type your meal below.")
            cleanUp()
        }
    }

    private func stopAndTranscribe() async {
        guard listening, let rec = recorder, let url = fileURL else { return }
        rec.stop()
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { cleanUp() }
        guard let data = try? Data(contentsOf: url), data.count > 2_000 else {
            error = String(localized: "food.voice.empty", defaultValue: "No speech detected · try again.")
            return
        }
        transcribing = true
        defer { transcribing = false }
        do {
            let words = try await transcribe(data, "audio/mp4")
            if words.isEmpty {
                error = String(localized: "food.voice.empty", defaultValue: "No speech detected · try again.")
            } else {
                onFinal?(words)
            }
        } catch {
            Log.data.error("voice.transcribe: \(String(describing: error), privacy: .public)")
            self.error = String(localized: "food.voice.transcribeFailed", defaultValue: "We couldn't write that down · try again or type your meal below.")
        }
    }

    private func cleanUp() {
        recorder = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }
}

extension SpeechDictation: AVAudioRecorderDelegate {
    /// The 90-second cap or an interruption ended the clip: treat it as the member's tap.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.listening else { return }
            await self.stopAndTranscribe()
        }
    }
}
