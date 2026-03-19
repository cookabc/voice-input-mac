import Foundation
import Speech

enum LiveSpeechError: Error, LocalizedError {
    case recognizerUnavailable
    var errorDescription: String? { "Speech recognizer is unavailable on this device or locale." }
}

final class LiveSpeechRecognizer {
    private let recognizer: SFSpeechRecognizer?
    // `request` is written on main thread (in beginTask/stop) and read on audio thread
    // (appendBuffer). Safety is guaranteed by the caller: AudioSession.stopRecording()
    // calls removeTap() before VoiceCoreService calls stopLiveTranscription(), so no
    // more appendBuffer calls can arrive after stop() nilifies this property.
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var confirmedText = ""
    private var isActive = false

    var onPartialResult: ((String) -> Void)?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start() throws {
        guard let rec = recognizer, rec.isAvailable else {
            throw LiveSpeechError.recognizerUnavailable
        }
        confirmedText = ""
        isActive = true
        beginTask(with: rec)
    }

    private func beginTask(with rec: SFSpeechRecognizer) {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            // Dispatch all state mutations to main thread.
            DispatchQueue.main.async {
                guard let self else { return }

                if let result {
                    let best = result.bestTranscription.formattedString
                    let full = self.confirmedText.isEmpty ? best : "\(self.confirmedText) \(best)"
                    self.onPartialResult?(full)

                    if result.isFinal {
                        self.confirmedText = full
                        // SFSpeechRecognizer tasks expire after ~1 min; restart automatically.
                        if self.isActive {
                            self.beginTask(with: rec)
                        }
                    }
                }

                if let err = error {
                    let code = (err as NSError).code
                    // 1110 = no speech detected; 203/301 = task cancelled — expected during stop.
                    guard code != 1110, code != 203, code != 301 else { return }
                    if self.isActive {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.beginTask(with: rec)
                        }
                    }
                }
            }
        }
    }

    // Called from the AVAudioEngine tap thread — must remain fast and non-blocking.
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

    static func requestAuthorization() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
    }
}
