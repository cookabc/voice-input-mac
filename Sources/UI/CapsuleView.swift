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
    var viewModel: CapsuleViewModel

    /// Per-bar amplitude weights: center bar tallest, outer bars shorter.
    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]

    var body: some View {
        HStack(spacing: 10) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusForegroundColor)
                    .frame(width: 24, height: 24)
            } else {
                // 5-bar waveform
                HStack(spacing: 3) {
                    ForEach(Array(weights.enumerated()), id: \.offset) { _, weight in
                        WaveformBar(level: viewModel.audioLevel, weight: weight)
                    }
                }
                .frame(width: 44, height: 32)
            }

            // Live text / status label
            if !displayText.isEmpty {
                Text(displayText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(statusForegroundColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .animation(.easeInOut(duration: 0.2), value: displayText.isEmpty)
    }

    private var displayText: String {
        switch viewModel.state {
        case .recording:     return viewModel.text
        case .transcribing:
            return viewModel.text.isEmpty ? "Transcribing…" : viewModel.text
        case .refining:      return "Refining…"
        case .cancelled:     return "Cancelled"
        case .success:       return viewModel.text.isEmpty ? "Done" : viewModel.text
        case .error:         return viewModel.text.isEmpty ? "Something went wrong" : viewModel.text
        }
    }

    private var leadingSymbol: String? {
        switch viewModel.state {
        case .cancelled:
            return "xmark.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .recording, .transcribing, .refining:
            return nil
        }
    }

    private var statusForegroundColor: Color {
        switch viewModel.state {
        case .success:
            return Color(red: 0.54, green: 0.95, blue: 0.67)
        case .error:
            return Color(red: 1.0, green: 0.82, blue: 0.28)
        case .cancelled, .recording, .transcribing, .refining:
            return .white
        }
    }
}

// MARK: - Single waveform bar

/// Displays one animated bar whose height tracks `level * weight`.
/// Uses smoothed attack/release for natural motion:
/// - Attack (level rising): 40 % of delta per frame
/// - Release (level falling): 15 % of delta per frame
/// A tiny per-bar jitter (±4 %) prevents the bars from looking robotic.
private struct WaveformBar: View {
    let level: Float
    let weight: Float

    @State private var smoothed: Float = 0
    @State private var timer: Timer?

    var body: some View {
        let clamped = min(1, max(0.05, smoothed))

        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.9))
            .frame(width: 4, height: CGFloat(clamped) * 28 + 4)
            .onAppear {
                startSmoothing()
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }

    /// Applies attack/release smoothing on a timer for natural motion.
    private func startSmoothing() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            Task { @MainActor in
                let jitter = Float.random(in: -0.04...0.04)
                let target = level * weight + jitter
                let rate: Float = target > smoothed ? 0.40 : 0.15
                let next = smoothed + (target - smoothed) * rate
                if abs(next - smoothed) > 0.001 {
                    smoothed = next
                }
            }
        }
    }
}
