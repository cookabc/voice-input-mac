import Foundation
import Speech

enum LiveSpeechError: Error, LocalizedError {
    case recognizerUnavailable
    var errorDescription: String? { "Speech recognizer is unavailable on this device or locale." }
}

// Runs one SFSpeechRecognizer pipeline per candidate locale in parallel.
// All channels receive the same audio buffers; we display the result from
// whichever channel is actively producing text (usually identified by length).
// This lets the app handle Chinese + English without language pre-selection.
final class LiveSpeechRecognizer {

    private struct Channel {
        let recognizer: SFSpeechRecognizer
        var request: SFSpeechAudioBufferRecognitionRequest?
        var task: SFSpeechRecognitionTask?
        var confirmedText = ""
        var latestFull = ""
    }

    // Safety guarantee (same as before): AudioSession.stopRecording() calls removeTap()
    // before VoiceCoreService calls stopLiveTranscription(), so appendBuffer() is never
    // called concurrently with the main-thread stop() that nils all requests.
    private var channels: [Channel] = []
    private var isActive = false

    var onPartialResult: ((String) -> Void)?

    init() {
        // Run zh-CN + zh-TW + system locale + en-US, deduplicating by identifier.
        // In practice this means ≤3 streams (zh-CN, zh-TW, en-US), covering the
        // common case of a user who switches between Chinese and English.
        let preferredIDs = ["zh-CN", "zh-TW", Locale.current.identifier, "en-US"]
        var seen = Set<String>()
        for id in preferredIDs {
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            if let rec = SFSpeechRecognizer(locale: Locale(identifier: id)) {
                channels.append(Channel(recognizer: rec))
            }
        }
    }

    func start() throws {
        let available = channels.filter { $0.recognizer.isAvailable }
        guard !available.isEmpty else { throw LiveSpeechError.recognizerUnavailable }
        isActive = true
        for i in channels.indices where channels[i].recognizer.isAvailable {
            channels[i].confirmedText = ""
            channels[i].latestFull = ""
            beginTask(index: i)
        }
    }

    private func beginTask(index i: Int) {
        guard i < channels.count else { return }
        let rec = channels[i].recognizer
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        channels[i].request = req

        channels[i].task = rec.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let result {
                    let segment = result.bestTranscription.formattedString
                    let confirmed = self.channels[i].confirmedText
                    let full = confirmed.isEmpty ? segment : "\(confirmed) \(segment)"
                    self.channels[i].latestFull = full

                    // Emit the longest result across all active channels.
                    // The channel whose locale matches the spoken language will always
                    // produce longer/more accurate text; others return empty or garbled.
                    let best = self.channels.map(\.latestFull).max(by: { $0.count < $1.count }) ?? full
                    self.onPartialResult?(best)

                    if result.isFinal {
                        self.channels[i].confirmedText = full
                        if self.isActive {
                            self.beginTask(index: i)   // restart for 1-min expiry
                        }
                    }
                }

                if let err = error {
                    let code = (err as NSError).code
                    guard code != 1110, code != 203, code != 301 else { return }
                    if self.isActive {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.beginTask(index: i)
                        }
                    }
                }
            }
        }
    }

    // Called from the AVAudioEngine tap thread.
    func appendBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        for channel in channels {
            channel.request?.append(buffer)
        }
    }

    func stop() {
        isActive = false
        for i in channels.indices {
            channels[i].request?.endAudio()
            channels[i].task?.finish()
            channels[i].task = nil
            channels[i].request = nil
            channels[i].confirmedText = ""
            channels[i].latestFull = ""
        }
    }

    static func requestAuthorization() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
    }
}

