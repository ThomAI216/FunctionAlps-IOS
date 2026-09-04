import AVFoundation
import Foundation
import Observation
import Speech

/// "Describe by voice": on-device speech recognition streaming into the describe field, the native
/// counterpart of the Expo card's instant SpeechRecognition path. The transcript is text the member
/// then sends to `analyze-meal` like a typed meal; no audio leaves the phone.
@MainActor
@Observable
final class SpeechDictation {
    private(set) var listening = false
    private(set) var interim = ""
    private(set) var error: String?
    /// The finished transcript, delivered once when listening stops.
    var onFinal: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer? { SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer() }
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    static var isAvailable: Bool { SFSpeechRecognizer() != nil }

    func toggle() {
        if listening { stop() } else { Task { await start() } }
    }

    private func start() async {
        error = nil
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            error = String(localized: "food.voice.denied", defaultValue: "Speech recognition isn't allowed. You can enable it in Settings, or type your meal below.")
            return
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            error = String(localized: "food.voice.micDenied", defaultValue: "The microphone isn't allowed. You can enable it in Settings, or type your meal below.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = String(localized: "food.voice.unavailable", defaultValue: "Voice isn't available right now · type your meal below.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            engine.prepare()
            try engine.start()
            listening = true
            interim = ""
            task = recognizer.recognitionTask(with: request) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.interim = result.bestTranscription.formattedString }
                    if err != nil || result?.isFinal == true { self.finish() }
                }
            }
        } catch {
            self.error = String(localized: "food.voice.failed", defaultValue: "Couldn't start listening · type your meal below.")
            stop()
        }
    }

    func stop() {
        guard listening else { return }
        request?.endAudio()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        // The final callback arrives after endAudio; hand over what we have if it does not.
        let words = interim
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if !words.isEmpty { onFinal?(words) }
        interim = ""
        task?.finish()
        task = nil
        request = nil
    }

    private func finish() {
        guard listening else { return }
        stop()
    }
}
