import AVFoundation

/// Lightweight TTS wrapper around AVSpeechSynthesizer for proofread-aloud.
/// Automatically picks the best system voice for the detected language.
@MainActor
final class TextToSpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = TextToSpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    /// Called on MainActor whenever speaking state changes.
    var onStateChange: ((Bool) -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak `text` aloud. If already speaking, stops first.
    func speak(_ text: String) {
        stop()
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0

        // Pick voice matching detected language. Falls back to system default.
        let lang = detectLanguage(text)
        if let voice = bestVoice(for: lang) {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
        isSpeaking = true
        onStateChange?(true)
    }

    func stop() {
        guard isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        onStateChange?(false)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synth: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
            self?.onStateChange?(false)
        }
    }

    nonisolated func speechSynthesizer(_ synth: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
            self?.onStateChange?(false)
        }
    }

    // MARK: - Helpers

    /// Simple heuristic: if >30% of characters are CJK, treat as Chinese.
    private func detectLanguage(_ text: String) -> String {
        let cjkCount = text.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let ratio = Double(cjkCount) / max(Double(text.count), 1)
        return ratio > 0.3 ? "zh-CN" : "en-US"
    }

    /// Prefer premium/enhanced voices when available.
    private func bestVoice(for lang: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(lang.prefix(2).description) }

        // Prefer premium quality voices.
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return voices.first ?? AVSpeechSynthesisVoice(language: lang)
    }
}
