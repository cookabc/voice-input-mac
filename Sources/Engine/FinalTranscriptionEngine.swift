import Foundation

struct FinalTranscriptionRequest: Sendable {
    let filePath: String
    let runtime: SpeechRuntimeStatus
    let selectedModel: SpeechModelIdentifier
}

protocol FinalTranscriptionEngine: Sendable {
    func transcribe(_ request: FinalTranscriptionRequest) async throws -> TranscriptionResult
}