import AVFoundation
import Foundation

@MainActor
protocol ConfigManaging: AnyObject {
    var asrProvider: String { get }
    var editBeforePaste: Bool { get }

    func migrateIfNeeded()
    func saveASRProvider(_ provider: String)

    @discardableResult
    func saveLLMConfiguration(baseURL: String, model: String, apiKey: String) -> Bool

    func saveEditBeforePaste(_ enabled: Bool)
}

@MainActor
protocol PromptManaging: AnyObject {
    var systemPrompt: String { get }

    func renderUserPrompt(text: String) -> String
    func seedDefaultsIfNeeded()
}

// MARK: - Audio Recording

/// Protocol for audio capture — extracted from `AudioSession` for testability.
/// Inspired by LuckyTrans's `ServiceProtocols.swift` pattern.
protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    var recordingPath: String { get }
    var recordingFormat: AVAudioFormat { get }
    var bufferSink: ((AVAudioPCMBuffer, AVAudioTime) -> Void)? { get set }
    var levelSink: ((Float) -> Void)? { get set }

    func startRecording() throws -> String
    func stopRecording()
}

// MARK: - Text Polishing

/// Protocol for LLM text polish — extracted from `LLMPolisher` actor.
protocol TextPolishing: Sendable {
    func polish(text: String, dictionary: [String]) async throws -> String
}

extension ConfigManager: ConfigManaging {}
extension PromptManager: PromptManaging {}
extension AudioSession: AudioRecording {}
extension LLMPolisher: TextPolishing {}