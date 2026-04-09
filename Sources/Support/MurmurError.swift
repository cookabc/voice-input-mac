import Foundation

/// Unified error type for Murmur, providing consistent user-facing messages
/// and recovery suggestions.
///
/// Inspired by LuckyTrans's `AppError` — centralized `LocalizedError` with
/// `errorDescription` and `recoverySuggestion` for all error categories.
enum MurmurError: LocalizedError {
    // Audio / Recording
    case alreadyRecording
    case engineStartFailed(String)
    case recognizerUnavailable

    // Transcription
    case audioFileNotFound(String)
    case transcriptionFailed(String)
    case transcriptionParseError(String)

    // LLM / Polishing
    case noApiKey
    case llmHTTPError(Int, String, String) // code, body, url
    case unexpectedLLMResponse

    // Text Insertion
    case pasteFailed(String)
    case accessibilityRequired

    // Model Management
    case modelExtractionFailed(String)

    // Keychain
    case keychainSaveFailed
    case keychainLoadFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A recording is already in progress."
        case .engineStartFailed(let msg):
            "Could not start audio engine: \(msg)"
        case .recognizerUnavailable:
            "Speech recognizer is unavailable on this device or locale."
        case .audioFileNotFound(let path):
            "Audio file not found: \(path)"
        case .transcriptionFailed(let msg):
            "Transcription failed: \(msg)"
        case .transcriptionParseError(let raw):
            "Unexpected transcription response: \(raw)"
        case .noApiKey:
            "No API key saved. Open Settings to enter your API key, or use a local endpoint that does not require one."
        case .llmHTTPError(let code, _, _):
            switch code {
            case 401: "API key invalid or expired (HTTP 401). Check your key in Settings."
            case 403: "Access denied (HTTP 403). Your API key may lack permission for this model."
            case 429: "Rate limited (HTTP 429). Wait a moment and try again."
            case 500...599: "Server error (HTTP \(code)). The API endpoint may be temporarily unavailable."
            default: "LLM request failed (HTTP \(code)). Check your Base URL and model in Settings."
            }
        case .unexpectedLLMResponse:
            "Unexpected response from LLM API."
        case .pasteFailed(let msg):
            "Failed to paste: \(msg)"
        case .accessibilityRequired:
            "Copied to clipboard. Grant Accessibility access in System Settings to enable auto-paste."
        case .modelExtractionFailed(let msg):
            msg
        case .keychainSaveFailed:
            "Failed to save credentials to Keychain."
        case .keychainLoadFailed:
            "Failed to load credentials from Keychain."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .alreadyRecording:
            "Wait for the current recording to finish."
        case .engineStartFailed:
            "Check your microphone settings and try again."
        case .recognizerUnavailable:
            "Ensure speech recognition is enabled in System Settings > Privacy & Security."
        case .audioFileNotFound:
            "Try recording again."
        case .transcriptionFailed, .transcriptionParseError:
            "Try again or switch to a different transcription model."
        case .noApiKey:
            "Open Settings and add your API key."
        case .llmHTTPError(let code, _, _):
            switch code {
            case 401, 403: "Check your API key in Settings."
            case 429: "Wait a moment and try again."
            default: "Check your Base URL and model in Settings."
            }
        case .unexpectedLLMResponse:
            "Try again or check the API endpoint configuration."
        case .pasteFailed:
            "Grant Accessibility permission in System Settings."
        case .accessibilityRequired:
            "Open System Settings > Privacy & Security > Accessibility."
        case .modelExtractionFailed:
            "Try downloading the model again."
        case .keychainSaveFailed, .keychainLoadFailed:
            "Check Keychain Access for permissions."
        }
    }
}
