import SwiftUI

// MARK: - ViewModel

@MainActor
@Observable
final class CapsuleViewModel {
    var audioLevel: Float = 0
    var text: String = ""
    var phase: DictationPhase = .idle
}

// MARK: - Capsule root view

struct CapsuleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var viewModel: CapsuleViewModel

    var body: some View {
        HStack(spacing: 14) {
            CapsuleGlyph(phase: viewModel.phase, audioLevel: viewModel.audioLevel)

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
            ZStack {
                // Layer 1: phase-tinted outer glow
                Capsule(style: .continuous)
                    .fill(phaseTint.opacity(0.08))
                    .blur(radius: 2)

                // Layer 2: frosted glass material
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)

                // Layer 3: gradient border
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                phaseTint.opacity(0.5),
                                phaseTint.opacity(0.15),
                                Color.white.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
        }
        .shadow(color: phaseTint.opacity(0.22), radius: 20, y: 8)
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 6)
    }

    private var titleText: String {
        viewModel.phase.capsuleTitle
    }

    private var detailText: String {
        let baseText = viewModel.text.isEmpty ? viewModel.phase.capsuleDetailPlaceholder : viewModel.text
        return summarized(text: baseText, for: viewModel.phase)
    }

    private var phaseTint: Color {
        switch viewModel.phase {
        case .recording:     MurmurDesignTokens.Capsule.recordingTint
        case .transcribing, .inserting:  MurmurDesignTokens.Capsule.transcribingTint
        case .refining:      MurmurDesignTokens.Capsule.refiningTint
        case .completed:     MurmurDesignTokens.Capsule.successTint
        case .failed:        MurmurDesignTokens.Capsule.errorTint
        case .cancelled:     MurmurDesignTokens.Capsule.cancelledTint
        case .idle, .editing: Color.white.opacity(0.2)
        }
    }

    private func summarized(text: String, for phase: DictationPhase) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return text }

        switch phase {
        case .recording:
            return suffixSummary(normalized, limit: 28)
        case .transcribing, .refining, .inserting:
            return suffixSummary(normalized, limit: 36)
        default:
            return normalized
        }
    }

    private func suffixSummary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return "…" + String(text.suffix(limit))
    }
}

private struct CapsuleGlyph: View {
    let phase: DictationPhase
    let audioLevel: Float

    var body: some View {
        switch phase {
        case .recording:
            RecordingGlyph(level: audioLevel)
        case .transcribing, .inserting:
            ActivityGlyph(symbol: "waveform.badge.magnifyingglass", tint: MurmurDesignTokens.Capsule.transcribingTint)
        case .refining:
            ActivityGlyph(symbol: "sparkles", tint: MurmurDesignTokens.Capsule.refiningTint)
        case .cancelled:
            StatusGlyph(symbol: "xmark", tint: MurmurDesignTokens.Capsule.cancelledTint)
        case .completed:
            StatusGlyph(symbol: "checkmark", tint: MurmurDesignTokens.Capsule.successTint)
        case .failed:
            StatusGlyph(symbol: "exclamationmark", tint: MurmurDesignTokens.Capsule.errorTint)
        case .idle, .editing:
            EmptyView()
        }
    }
}

// MARK: - Recording Glyph (7 bars with gradient fills + pulsing ring)

private struct RecordingGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let level: Float

    private let barCount = 7
    private let weights: [CGFloat] = [0.36, 0.55, 0.78, 1.0, 0.80, 0.58, 0.38]

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                // Pulsing ring behind bars
                Circle()
                    .stroke(
                        MurmurDesignTokens.Capsule.recordingTint.opacity(reduceMotion ? 0.15 : 0.10 + Double(level) * 0.18),
                        lineWidth: 1.5
                    )
                    .scaleEffect(reduceMotion ? 1.0 : 1.0 + CGFloat(level) * 0.12)

                // Bar visualizer
                HStack(alignment: .center, spacing: 2.8) {
                    ForEach(0..<barCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        MurmurDesignTokens.Capsule.recordingTint,
                                        MurmurDesignTokens.Capsule.recordingTint.opacity(0.55),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(
                                width: 3.2,
                                height: barHeight(weight: weights[index], index: index, time: time)
                            )
                    }
                }
            }
            .frame(width: MurmurDesignTokens.Capsule.iconSize, height: MurmurDesignTokens.Capsule.iconSize)
        }
    }

    private func barHeight(weight: CGFloat, index: Int, time: TimeInterval) -> CGFloat {
        let baseLevel = CGFloat(max(0.08, min(1, level)))
        let oscillation: CGFloat

        if reduceMotion {
            oscillation = 0
        } else {
            let phase = time * 6.8 + Double(index) * 0.48
            oscillation = CGFloat((sin(phase) + 1) * 0.5) * 0.20
        }

        return 6 + ((baseLevel * weight) + oscillation) * 20
    }
}

// MARK: - Activity Glyph (orbiting arc ring with AngularGradient)

private struct ActivityGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let symbol: String
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = reduceMotion ? 0.15 : CGFloat((sin(t * 3.6) + 1) * 0.5)
            let rotation = reduceMotion ? 0.0 : t.truncatingRemainder(dividingBy: 2.0) / 2.0 * 360

            ZStack {
                // Soft glow base
                Circle()
                    .fill(tint.opacity(0.10 + pulse * 0.06))

                // Orbiting arc ring
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        AngularGradient(
                            colors: [tint.opacity(0), tint.opacity(0.7), tint],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation))

                // Inner pulse ring
                Circle()
                    .stroke(tint.opacity(0.18 + pulse * 0.18), lineWidth: 1.0)
                    .scaleEffect(0.72 + pulse * 0.06)

                // Icon
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .frame(width: MurmurDesignTokens.Capsule.iconSize, height: MurmurDesignTokens.Capsule.iconSize)
        }
    }
}

// MARK: - Status Glyph (scale + opacity entrance animation)

private struct StatusGlyph: View {
    let symbol: String
    let tint: Color

    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.5), tint.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )

            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .scaleEffect(appeared ? 1.0 : 0.4)
                .opacity(appeared ? 1.0 : 0)
        }
        .frame(width: MurmurDesignTokens.Capsule.iconSize, height: MurmurDesignTokens.Capsule.iconSize)
        .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.35)) { appeared = true } }
    }
}
