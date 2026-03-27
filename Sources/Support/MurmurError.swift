import Foundation

/// Unified error model for the entire Murmur pipeline.
/// Each case carries a human-readable message and optional recovery metadata.
enum MurmurError: Error, LocalizedError, Identifiable {
    // MARK: - Runtime / Setup
    case runtimeNotReady(detail: String)
    case coliMissing
    case permissionDenied(detail: String)

    // MARK: - Recording
    case recordingStartFailed(underlying: String)
    case recordingAlreadyActive
    case noActiveRecording

    // MARK: - Transcription
    case transcriptionFailed(underlying: String)
    case noRecordingToTranscribe

    // MARK: - LLM Polish
    case llmNoAPIKey
    case llmEndpointUnreachable(detail: String)
    case llmModelMissing(model: String)
    case llmRequestFailed(underlying: String)

    // MARK: - Paste / Clipboard
    case accessibilityNotGranted
    case noTextAvailable(action: String)

    // MARK: - Playback
    case clipPlaybackFailed(underlying: String)

    var id: String { category.rawValue + "_" + String(describing: self).prefix(40) }

    enum Category: String {
        case runtime, recording, transcription, llm, paste, playback
    }

    var category: Category {
        switch self {
        case .runtimeNotReady, .coliMissing, .permissionDenied: return .runtime
        case .recordingStartFailed, .recordingAlreadyActive, .noActiveRecording: return .recording
        case .transcriptionFailed, .noRecordingToTranscribe: return .transcription
        case .llmNoAPIKey, .llmEndpointUnreachable, .llmModelMissing, .llmRequestFailed: return .llm
        case .accessibilityNotGranted, .noTextAvailable: return .paste
        case .clipPlaybackFailed: return .playback
        }
    }

    var isFatal: Bool {
        switch self {
        case .coliMissing, .runtimeNotReady: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .runtimeNotReady(let d): return "Runtime not ready: \(d)"
        case .coliMissing: return "coli binary not found. Install @marswave/coli to enable transcription."
        case .permissionDenied(let d): return "Permission denied: \(d)"
        case .recordingStartFailed(let u): return "Recording failed to start: \(u)"
        case .recordingAlreadyActive: return "Recording is already running."
        case .noActiveRecording: return "No active recording to stop."
        case .transcriptionFailed(let u): return "Transcription failed: \(u)"
        case .noRecordingToTranscribe: return "No recording available to transcribe."
        case .llmNoAPIKey: return "Enter your API key in Settings, or switch to a local model endpoint."
        case .llmEndpointUnreachable(let d): return "LLM endpoint unreachable: \(d)"
        case .llmModelMissing(let m): return "Model \"\(m)\" not found. Pull it or change model in Settings."
        case .llmRequestFailed(let u): return "LLM request failed: \(u)"
        case .accessibilityNotGranted: return "Copied to clipboard. Grant Accessibility in System Settings to enable auto-paste."
        case .noTextAvailable(let a): return "No text available to \(a)."
        case .clipPlaybackFailed(let u): return "Could not play clip: \(u)"
        }
    }
}
