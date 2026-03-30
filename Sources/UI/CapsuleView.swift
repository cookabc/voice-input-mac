import SwiftUI

// MARK: - ViewModel

enum CapsuleState {
    case recording, transcribing, refining, cancelled
}

@MainActor
final class CapsuleViewModel: ObservableObject {
    @Published var audioLevel: Float = 0
    @Published var text: String = ""
    @Published var state: CapsuleState = .recording
}

// MARK: - Capsule root view

struct CapsuleView: View {
    @ObservedObject var viewModel: CapsuleViewModel

    /// Per-bar amplitude weights: center bar tallest, outer bars shorter.
    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]

    var body: some View {
        HStack(spacing: 10) {
            // 5-bar waveform
            HStack(spacing: 3) {
                ForEach(Array(weights.enumerated()), id: \.offset) { _, weight in
                    WaveformBar(level: viewModel.audioLevel, weight: weight)
                }
            }
            .frame(width: 44, height: 32)

            // Live text / status label
            if !displayText.isEmpty {
                Text(displayText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
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

    var body: some View {
        let _ = updateSmoothed()
        let clamped = min(1, max(0.05, smoothed))

        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.9))
            .frame(width: 4, height: CGFloat(clamped) * 28 + 4)
    }

    /// Called on every SwiftUI body evaluation; applies attack/release smoothing.
    private func updateSmoothed() {
        let jitter = Float.random(in: -0.04...0.04)
        let target = level * weight + jitter
        let rate: Float = target > smoothed ? 0.40 : 0.15
        let next = smoothed + (target - smoothed) * rate
        // Avoid triggering a view update loop; only write when the delta matters.
        if abs(next - smoothed) > 0.001 {
            DispatchQueue.main.async { smoothed = next }
        }
    }
}
