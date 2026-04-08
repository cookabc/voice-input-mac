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
        case .idle:              "Ready"
        case .recording:         "Listening"
        case .transcribing:      "Transcribing"
        case .refining:          "Refining"
        case .editing:           "Editing"
        case .inserting:         "Inserting"
        case .completed:         "Done"
        case .cancelled:         "Cancelled"
        case .failed:            "Error"
        }
    }

    var capsuleDetailPlaceholder: String {
        switch self {
        case .idle:              ""
        case .recording:         "Speak now"
        case .transcribing:      "Running final speech pass"
        case .refining:          "Applying correction prompt"
        case .editing:           "Review your transcript"
        case .inserting:         "Pasting…"
        case .completed(let m):  m.isEmpty ? "Transcript inserted" : m
        case .cancelled(let m):  m.isEmpty ? "Nothing was inserted" : m
        case .failed(let m):     m.isEmpty ? "Something went wrong" : m
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
        case .recording:     .red
        case .transcribing:  .blue
        case .refining:      .purple
        case .editing:       .teal
        case .inserting:     .blue
        case .completed:     .green
        case .cancelled:     .secondary
        case .failed:        .yellow
        }
    }

    var menuBarAccessibilityLabel: String {
        switch self {
        case .idle:              "Murmur"
        case .recording:         "Murmur - Recording"
        case .transcribing:      "Murmur - Transcribing"
        case .refining:          "Murmur - Refining"
        case .editing:           "Murmur - Reviewing Transcript"
        case .inserting:         "Murmur - Inserting"
        case .completed:         "Murmur - Success"
        case .cancelled:         "Murmur - Cancelled"
        case .failed:            "Murmur - Error"
        }
    }

    var menuBarStatusLine: String {
        switch self {
        case .idle:              "Status: Ready"
        case .recording:         "Status: Recording…"
        case .transcribing:      "Status: Transcribing…"
        case .refining:          "Status: Refining…"
        case .editing:           "Status: Reviewing transcript…"
        case .inserting:         "Status: Inserting…"
        case .completed(let m):  "Status: \(m.isEmpty ? "Done" : m)"
        case .cancelled(let m):  "Status: \(m.isEmpty ? "Cancelled" : m)"
        case .failed(let m):     "Status: \(m.isEmpty ? "Something went wrong" : m)"
        }
    }
}
