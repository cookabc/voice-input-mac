import SwiftUI

// MARK: - ViewModel

enum CapsuleState {
    case recording, transcribing, refining, cancelled, success, error
}

@MainActor
@Observable
final class CapsuleViewModel {
    var audioLevel: Float = 0
    var text: String = ""
    var state: CapsuleState = .recording
}

// MARK: - Capsule root view

struct CapsuleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var viewModel: CapsuleViewModel

    var body: some View {
        HStack(spacing: 14) {
            CapsuleGlyph(state: viewModel.state, audioLevel: viewModel.audioLevel)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text(detailText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, MurmurDesignTokens.Capsule.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: MurmurDesignTokens.Capsule.height, maxHeight: MurmurDesignTokens.Capsule.height)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(MurmurDesignTokens.Capsule.borderColor, lineWidth: 1)
                )
        }
        .shadow(color: MurmurDesignTokens.Capsule.shadowColor, radius: 18, y: 10)
        .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.22), value: viewModel.state)
        .animation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.18), value: detailText)
    }

    private var titleText: String {
        switch viewModel.state {
        case .recording:
            return "Listening"
        case .transcribing:
            return "Transcribing"
        case .refining:
            return "Refining"
        case .cancelled:
            return "Cancelled"
        case .success:
            return "Done"
        case .error:
            return "Error"
        }
    }

    private var detailText: String {
        switch viewModel.state {
        case .recording:
            return viewModel.text.isEmpty ? "Speak now" : viewModel.text
        case .transcribing:
            return viewModel.text.isEmpty ? "Processing recorded speech" : viewModel.text
        case .refining:
            return viewModel.text.isEmpty ? "Applying correction prompt" : viewModel.text
        case .cancelled:
            return viewModel.text.isEmpty ? "Nothing was inserted" : viewModel.text
        case .success:
            return viewModel.text.isEmpty ? "Transcript inserted" : viewModel.text
        case .error:
            return viewModel.text.isEmpty ? "Something went wrong" : viewModel.text
        }
    }
}

private struct CapsuleGlyph: View {
    let state: CapsuleState
    let audioLevel: Float

    var body: some View {
        switch state {
        case .recording:
            RecordingGlyph(level: audioLevel)
        case .transcribing:
            ActivityGlyph(symbol: "waveform.badge.magnifyingglass", tint: MurmurDesignTokens.Capsule.transcribingTint)
        case .refining:
            ActivityGlyph(symbol: "sparkles", tint: MurmurDesignTokens.Capsule.refiningTint)
        case .cancelled:
            StatusGlyph(symbol: "xmark", tint: MurmurDesignTokens.Capsule.cancelledTint)
        case .success:
            StatusGlyph(symbol: "checkmark", tint: MurmurDesignTokens.Capsule.successTint)
        case .error:
            StatusGlyph(symbol: "exclamationmark", tint: MurmurDesignTokens.Capsule.errorTint)
        }
    }
}

private struct RecordingGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let level: Float

    private let weights: [CGFloat] = [0.48, 0.78, 1.0, 0.74, 0.54]

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 24.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 3.5) {
                ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MurmurDesignTokens.Capsule.recordingTint.opacity(0.92))
                        .frame(
                            width: 4,
                            height: barHeight(weight: weight, index: index, time: time)
                        )
                }
            }
            .frame(width: MurmurDesignTokens.Capsule.iconSize, height: MurmurDesignTokens.Capsule.iconSize)
            .padding(.horizontal, 1)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(MurmurDesignTokens.Capsule.recordingTint.opacity(0.12))
            )
        }
    }

    private func barHeight(weight: CGFloat, index: Int, time: TimeInterval) -> CGFloat {
        let baseLevel = CGFloat(max(0.08, min(1, level)))
        let oscillation: CGFloat

        if reduceMotion {
            oscillation = 0
        } else {
            let phase = time * 6.2 + Double(index) * 0.55
            oscillation = CGFloat((sin(phase) + 1) * 0.5) * 0.18
        }

        return 8 + ((baseLevel * weight) + oscillation) * 18
    }
}

private struct ActivityGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let symbol: String
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 24.0)) { timeline in
            let phase = reduceMotion ? 0.15 : CGFloat((sin(timeline.date.timeIntervalSinceReferenceDate * 3.6) + 1) * 0.5)

            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                Circle()
                    .stroke(tint.opacity(0.22 + phase * 0.24), lineWidth: 1.2)
                    .scaleEffect(1 + phase * 0.08)

                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .frame(width: MurmurDesignTokens.Capsule.iconSize, height: MurmurDesignTokens.Capsule.iconSize)
        }
    }
}

private struct StatusGlyph: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
            Circle()
                .stroke(tint.opacity(0.28), lineWidth: 1.2)

            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: MurmurDesignTokens.Capsule.iconSize, height: MurmurDesignTokens.Capsule.iconSize)
    }
}
