import SwiftUI

struct ShellPanelView: View {
    @ObservedObject var viewModel: ShellViewModel
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }

    private var panelBackground: Color {
        dark ? Color(red: 0.08, green: 0.12, blue: 0.13)
             : Color(red: 0.96, green: 0.96, blue: 0.95)
    }
    private var panelSurface: Color {
        dark ? Color(red: 0.12, green: 0.18, blue: 0.18)
             : Color(red: 0.92, green: 0.93, blue: 0.92)
    }
    private var panelSurfaceStrong: Color {
        dark ? Color(red: 0.18, green: 0.24, blue: 0.23)
             : Color(red: 0.86, green: 0.88, blue: 0.87)
    }
    private var panelText: Color {
        dark ? Color(red: 0.95, green: 0.94, blue: 0.89)
             : Color(red: 0.12, green: 0.13, blue: 0.15)
    }
    private var panelMuted: Color {
        dark ? Color(red: 0.67, green: 0.73, blue: 0.70)
             : Color(red: 0.42, green: 0.45, blue: 0.43)
    }
    private let panelAccent = Color(red: 0.90, green: 0.58, blue: 0.31)
    private var panelAccentSoft: Color {
        dark ? Color(red: 0.31, green: 0.52, blue: 0.49)
             : Color(red: 0.22, green: 0.46, blue: 0.42)
    }
    private var panelDanger: Color {
        dark ? Color(red: 0.75, green: 0.36, blue: 0.27)
             : Color(red: 0.80, green: 0.28, blue: 0.20)
    }

    private var heroTint: Color {
        if viewModel.isRecordingActive { return panelDanger }
        if viewModel.isReady { return panelAccent }
        if viewModel.runtimeBadge == "Needs setup" { return Color(red: 0.85, green: 0.70, blue: 0.22) }
        return panelSurfaceStrong
    }

    private var badgeTint: Color {
        switch viewModel.runtimeBadge {
        case "Ready":       return panelAccent
        case "Needs setup": return Color(red: 0.85, green: 0.70, blue: 0.22)
        case "Offline":     return panelDanger
        default:            return panelMuted
        }
    }

    var body: some View {
        ZStack {
            // ── MAIN PANEL ──
            ZStack {
            LinearGradient(
                colors: [panelBackground, dark ? Color(red: 0.10, green: 0.16, blue: 0.17) : Color(red: 0.93, green: 0.94, blue: 0.93)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(panelAccent.opacity(dark ? 0.18 : 0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 30)
                .offset(x: 130, y: -170)

            Circle()
                .fill(panelAccentSoft.opacity(dark ? 0.22 : 0.14))
                .frame(width: 180, height: 180)
                .blur(radius: 24)
                .offset(x: -140, y: 170)

            VStack(spacing: 0) {
                // ── PINNED HEADER ──
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Murmur")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Dictate & polish")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(panelMuted)
                    }

                    Spacer()

                    if !viewModel.isReady {
                        Text(viewModel.runtimeBadge)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(badgeTint.opacity(0.18), in: Capsule())
                    }

                    Button {
                        viewModel.openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(panelMuted)
                            .frame(width: 24, height: 24)
                            .background((dark ? Color.white : Color.black).opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings")

                    Button {
                        viewModel.onRequestQuit?()
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(panelMuted)
                            .frame(width: 24, height: 24)
                            .background((dark ? Color.white : Color.black).opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Quit Voice Input")

                    Button {
                        viewModel.onRequestDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(panelMuted)
                            .frame(width: 24, height: 24)
                            .background((dark ? Color.white : Color.black).opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // ── SCROLLABLE CONTENT ──
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !viewModel.isReady {
                            Text("\(viewModel.runtimeBadge): \(viewModel.detail)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(panelMuted)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(panelSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // ── Record + Clip side by side ──
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                if viewModel.isRecordingActive {
                                    viewModel.stopRecording()
                                } else {
                                    viewModel.startRecording()
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: viewModel.isRecordingActive ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 22, weight: .bold))
                                    Text(viewModel.isRecordingActive ? "Stop" : "Record")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                    if viewModel.isRecordingActive {
                                        Text(viewModel.recordingTimeString)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 84)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(heroTint)
                            .disabled(!viewModel.canStartRecording && !viewModel.canStopRecording)
                            .frame(maxWidth: .infinity)

                            ZStack(alignment: .top) {
                                if viewModel.isRecordingActive {
                                    VStack(spacing: 10) {
                                        WaveformBarsView(level: viewModel.micLevel, color: panelDanger)
                                        Text("Listening\u{2026}")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(panelDanger.opacity(0.8))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(panelDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                } else if viewModel.isTranscribing {
                                    VStack(spacing: 8) {
                                        ProgressView().scaleEffect(0.85)
                                        Text("Transcribing\u{2026}")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(panelMuted)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(panelSurface.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                } else if !viewModel.recordingPath.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "waveform")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(panelAccentSoft)
                                            Text("Clip ready")
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(panelText)
                                        }
                                        Text(URL(fileURLWithPath: viewModel.recordingPath).lastPathComponent)
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundStyle(panelMuted.opacity(0.7))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Button {
                                            viewModel.toggleClipPlayback()
                                        } label: {
                                            Label(viewModel.isPlayingClip ? "Stop" : "Play",
                                                  systemImage: viewModel.isPlayingClip ? "stop.fill" : "play.fill")
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(panelAccentSoft)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(12)
                                    .background(panelSurface.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 84)
                        }

                        if !viewModel.actionError.isEmpty {
                            Text(viewModel.actionError)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(dark ? Color(red: 1.0, green: 0.84, blue: 0.78) : Color(red: 0.60, green: 0.15, blue: 0.08))
                                .textSelection(.enabled)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((dark ? Color(red: 0.33, green: 0.15, blue: 0.13) : Color(red: 0.98, green: 0.90, blue: 0.88)).opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        if !viewModel.transcriptText.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                // ── Transcript ──
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Transcript")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(panelMuted)
                                        Spacer()
                                        Button {
                                            viewModel.clearTranscript()
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(panelMuted)
                                                .frame(width: 20, height: 20)
                                                .background((dark ? Color.white : Color.black).opacity(0.10), in: Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Text(viewModel.transcriptText)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(panelText)
                                        .textSelection(.enabled)

                                    if !viewModel.transcriptMeta.isEmpty {
                                        Text(viewModel.transcriptMeta)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(panelMuted)
                                    }

                                    HStack(spacing: 8) {
                                        Button {
                                            viewModel.copyTranscript()
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(panelMuted)

                                        Spacer()

                                        Button {
                                            viewModel.polishTranscript()
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: viewModel.isPolishing ? "hourglass" : "sparkles")
                                                    .font(.system(size: 11, weight: .bold))
                                                Text(viewModel.isPolishing ? "Polishing\u{2026}" : "Polish")
                                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                            }
                                            .padding(.horizontal, 4)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Color(red: 0.62, green: 0.46, blue: 0.86))
                                        .disabled(!viewModel.canPolish)
                                    }
                                }
                                .padding(16)

                                // ── Polished (inline, same card) ──
                                if !viewModel.polishedText.isEmpty {
                                    Rectangle()
                                        .fill(Color(red: 0.62, green: 0.46, blue: 0.86).opacity(0.2))
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)

                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 10, weight: .bold))
                                            Text("Polished")
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                        }
                                        .foregroundStyle(Color(red: 0.72, green: 0.58, blue: 0.94))

                                        Text(viewModel.polishedText)
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(panelText)
                                            .textSelection(.enabled)

                                        Button {
                                            viewModel.copyPolished()
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Color(red: 0.62, green: 0.46, blue: 0.86))
                                    }
                                    .padding(16)
                                    .background(Color(red: 0.62, green: 0.46, blue: 0.86).opacity(dark ? 0.12 : 0.07))
                                }
                            }
                            .background(panelSurfaceStrong.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                    .animation(.easeOut(duration: 0.18), value: viewModel.recordingPath)
                    .animation(.easeOut(duration: 0.18), value: viewModel.isRecordingActive)
                    .animation(.easeOut(duration: 0.18), value: viewModel.isTranscribing)
                    .animation(.easeOut(duration: 0.18), value: viewModel.transcriptText.isEmpty)
                    .animation(.easeOut(duration: 0.18), value: viewModel.polishedText.isEmpty)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                }

                // ── STATUS FOOTER removed ──
            }
        }

        // ── SETTINGS PANEL (sibling in root ZStack — required for text field focus) ──
        if viewModel.showSettings {
            SettingsView(viewModel: viewModel)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal:   .move(edge: .trailing)
                ))
        }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(minWidth: 380, idealWidth: 408, maxWidth: .infinity, minHeight: 360, idealHeight: 500, maxHeight: .infinity)
        .foregroundStyle(panelText)
        .animation(.easeInOut(duration: 0.25), value: viewModel.showSettings)
        .onAppear {
            viewModel.refreshRuntime()
        }
    }
}

// MARK: - Supporting Views

private struct PulsingDot: View {
    let color: Color
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    scale = 0.45
                }
            }
    }
}

private struct WaveformBarsView: View {
    let level: Float
    let color: Color
    // Mountain-shaped multipliers — center bar is tallest.
    private let multipliers: [CGFloat] = [0.25, 0.55, 0.80, 1.0, 0.80, 0.55, 0.25]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(multipliers.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: max(4, CGFloat(level) * multipliers[i] * 44))
                    .animation(.easeInOut(duration: 0.10), value: level)
            }
        }
        .frame(width: 40, height: 44)
    }
}
