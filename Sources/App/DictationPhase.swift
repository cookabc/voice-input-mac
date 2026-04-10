import SwiftUI

/// Single source of truth for the dictation pipeline state.
/// Replaces the former `DictationCoordinator.State`, `CapsuleState`,
/// and `MenuBarController.RuntimeState` — three near-identical enums
/// that had to be kept in sync manually.
enum DictationPhase: Equatable {
    case idle
    case recording
    case transcribing
    case refining
    case editing
    case inserting
    case completed(String)
    case cancelled(String)
    case failed(String)

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed: true
        default: false
        }
    }

    var isActive: Bool {
        switch self {
        case .idle: false
        default: true
        }
    }

    var pinnedCapsuleText: String? {
        switch self {
        case .completed(let message), .cancelled(let message), .failed(let message):
            return message.isEmpty ? nil : message
        default:
            return nil
        }
    }

    // MARK: - Capsule visual mapping

    var capsuleTitle: String {
        switch self {
        case .idle:              String(localized: "Ready")
        case .recording:         String(localized: "Listening")
        case .transcribing:      String(localized: "Transcribing")
        case .refining:          String(localized: "Refining")
        case .editing:           String(localized: "Editing")
        case .inserting:         String(localized: "Inserting")
        case .completed:         String(localized: "Done")
        case .cancelled:         String(localized: "Cancelled")
        case .failed:            String(localized: "Error")
        }
    }

    var capsuleDetailPlaceholder: String {
        switch self {
        case .idle:              ""
        case .recording:         String(localized: "Speak now")
        case .transcribing:      String(localized: "Running final speech pass")
        case .refining:          String(localized: "Applying correction prompt")
        case .editing:           String(localized: "Review your transcript")
        case .inserting:         String(localized: "Pasting…")
        case .completed(let m):  m.isEmpty ? String(localized: "Transcript inserted") : m
        case .cancelled(let m):  m.isEmpty ? String(localized: "Nothing was inserted") : m
        case .failed(let m):     m.isEmpty ? String(localized: "Something went wrong") : m
        }
    }

    // MARK: - Menu bar visual mapping

    var menuBarSymbol: String {
        switch self {
        case .idle:          "mic.fill"
        case .recording:     "waveform.and.mic"
        case .transcribing:  "text.bubble.fill"
        case .refining:      "sparkles"
        case .editing:       "square.and.pencil"
        case .inserting:     "text.bubble.fill"
        case .completed:     "checkmark.circle.fill"
        case .cancelled:     "xmark.circle.fill"
        case .failed:        "exclamationmark.triangle.fill"
        }
    }

    var menuBarTint: Color {
        switch self {
        case .idle:          .primary
        case .recording:     MurmurDesignTokens.Capsule.recordingTint
        case .transcribing:  MurmurDesignTokens.Capsule.transcribingTint
        case .refining:      MurmurDesignTokens.Capsule.refiningTint
        case .editing:       MurmurDesignTokens.Capsule.editingTint
        case .inserting:     MurmurDesignTokens.Capsule.insertingTint
        case .completed:     MurmurDesignTokens.Capsule.successTint
        case .cancelled:     MurmurDesignTokens.Capsule.cancelledTint
        case .failed:        MurmurDesignTokens.Capsule.errorTint
        }
    }

    var menuBarAccessibilityLabel: String {
        switch self {
        case .idle:              String(localized: "Murmur")
        case .recording:         String(localized: "Murmur - Recording")
        case .transcribing:      String(localized: "Murmur - Transcribing")
        case .refining:          String(localized: "Murmur - Refining")
        case .editing:           String(localized: "Murmur - Reviewing Transcript")
        case .inserting:         String(localized: "Murmur - Inserting")
        case .completed:         String(localized: "Murmur - Success")
        case .cancelled:         String(localized: "Murmur - Cancelled")
        case .failed:            String(localized: "Murmur - Error")
        }
    }

    var menuBarStatusLine: String {
        switch self {
        case .idle:              String(localized: "Status: Ready")
        case .recording:         String(localized: "Status: Recording…")
        case .transcribing:      String(localized: "Status: Transcribing…")
        case .refining:          String(localized: "Status: Refining…")
        case .editing:           String(localized: "Status: Reviewing transcript…")
        case .inserting:         String(localized: "Status: Inserting…")
        case .completed(let m):  String(localized: "Status: \(m.isEmpty ? String(localized: "Done") : m)")
        case .cancelled(let m):  String(localized: "Status: \(m.isEmpty ? String(localized: "Cancelled") : m)")
        case .failed(let m):     String(localized: "Status: \(m.isEmpty ? String(localized: "Something went wrong") : m)")
        }
    }
}
