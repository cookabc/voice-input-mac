import Foundation
import Speech

enum LiveSpeechError: Error, LocalizedError {
    case recognizerUnavailable
    var errorDescription: String? { "Speech recognizer is unavailable on this device or locale." }
}

/// Single-locale SFSpeechRecognizer pipeline.
/// Receives audio buffers from AudioSession via `appendBuffer(_:at:)`,
/// emits partial transcripts through `onPartialResult`.
/// Handles the 1-minute recognition-task expiry by auto-restarting.
final class LiveSpeechRecognizer {

    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var confirmedText = ""
    private var isActive = false

    var onPartialResult: ((String) -> Void)?

    /// Creates a recognizer for a single locale (e.g. "zh-CN", "en-US").
    init(locale: String = "zh-CN") {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw LiveSpeechError.recognizerUnavailable
        }
        isActive = true
        confirmedText = ""
        beginTask()
    }

    private func beginTask() {
        guard let recognizer else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let result {
                    let segment = result.bestTranscription.formattedString
                    let confirmed = self.confirmedText
                    let full = confirmed.isEmpty ? segment : "\(confirmed) \(segment)"

                    self.onPartialResult?(full)

                    if result.isFinal {
                        self.confirmedText = full
                        // Auto-restart — SFSpeechRecognitionTask expires after ~1 min.
                        if self.isActive { self.beginTask() }
                    }
                }

                if let err = error {
                    let code = (err as NSError).code
                    // 1110 = no speech detected, 203 = cancelled, 301 = service reset
                    guard code != 1110, code != 203, code != 301 else { return }
                    if self.isActive {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.beginTask()
                        }
                    }
                }
            }
        }
    }

    /// Called from the AVAudioEngine tap thread.
    func appendBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        request?.append(buffer)
    }

    func stop() {
        isActive = false
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        confirmedText = ""
    }

    /// The latest accumulated transcript text (confirmed + in-flight).
    var latestText: String { confirmedText }

    static func requestAuthorization() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
    }
}

