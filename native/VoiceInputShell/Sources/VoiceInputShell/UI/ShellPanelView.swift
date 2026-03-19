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
                        Text("Voice Input")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("On-device dictation")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(panelMuted)
                    }

                    Spacer()

                    Text(viewModel.runtimeBadge)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(badgeTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(badgeTint.opacity(0.18), in: Capsule())

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
                    .contextMenu {
                        Button("Quit Voice Input", role: .destructive) {
                            viewModel.onRequestQuit?()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // ── SCROLLABLE CONTENT ──
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !viewModel.isReady {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(viewModel.title)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(panelText)
                                    .lineLimit(2)
                                Text(viewModel.detail)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(panelMuted)
                                    .lineSpacing(2)
                            }
                            .padding(14)
                            .background(panelSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Button {
                            if viewModel.isRecordingActive {
                                viewModel.stopRecording()
                            } else {
                                viewModel.startRecording()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: viewModel.isRecordingActive ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 16, weight: .bold))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(viewModel.isRecordingActive ? "Stop now" : "Start dictation")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                    Text(viewModel.recordingLine)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(panelText.opacity(0.84))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(heroTint)
                        .disabled(!viewModel.canStartRecording && !viewModel.canStopRecording)

                        if viewModel.isRecordingActive && !viewModel.liveTranscript.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Live")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(panelDanger.opacity(0.8))
                                Text(viewModel.liveTranscript)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(panelText.opacity(0.85))
                                    .italic()
                                Text("Listening\u{2026}")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(panelMuted)
                            }
                            .padding(14)
                            .background(panelDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }

                        if !viewModel.recordingPath.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform.badge.mic")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(panelAccentSoft)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Clip recorded")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(panelText)
                                    Text(URL(fileURLWithPath: viewModel.recordingPath).lastPathComponent)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(panelMuted)
                                }
                                Spacer()
                                Button {
                                    viewModel.toggleClipPlayback()
                                } label: {
                                    Image(systemName: viewModel.isPlayingClip ? "stop.fill" : "play.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(panelAccent)
                                        .frame(width: 32, height: 32)
                                        .background(panelAccent.opacity(0.15), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(panelSurface.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }

                        if !viewModel.actionError.isEmpty {
                            Text(viewModel.actionError)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(dark ? Color(red: 1.0, green: 0.84, blue: 0.78) : Color(red: 0.60, green: 0.15, blue: 0.08))
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((dark ? Color(red: 0.33, green: 0.15, blue: 0.13) : Color(red: 0.98, green: 0.90, blue: 0.88)).opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        if !viewModel.transcriptText.isEmpty {
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

                                HStack(spacing: 10) {
                                    Button("Copy") {
                                        viewModel.copyTranscript()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(panelAccentSoft)

                                    Button("Paste") {
                                        viewModel.pasteTranscript()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(panelAccent)

                                    Spacer()

                                    Button {
                                        viewModel.polishTranscript()
                                    } label: {
                                        Label(
                                            viewModel.isPolishing ? "Polishing\u{2026}" : "\u{2736} Polish",
                                            systemImage: viewModel.isPolishing ? "hourglass" : "sparkles"
                                        )
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(Color(red: 0.62, green: 0.46, blue: 0.86))
                                    .disabled(!viewModel.canPolish)
                                }
                            }
                            .padding(16)
                            .background(panelSurfaceStrong.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }

                        if !viewModel.polishedText.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Polished", systemImage: "sparkles")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.72, green: 0.58, blue: 0.94))

                                Text(viewModel.polishedText)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(panelText)
                                    .textSelection(.enabled)

                                HStack(spacing: 10) {
                                    Button("Copy") {
                                        viewModel.copyPolished()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(panelAccentSoft)

                                    Button("Paste") {
                                        viewModel.pastePolished()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color(red: 0.62, green: 0.46, blue: 0.86))
                                }
                            }
                            .padding(16)
                            .background(
                                Color(red: 0.62, green: 0.46, blue: 0.86).opacity(dark ? 0.15 : 0.09),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }

                        Button {
                            viewModel.transcribeLatestRecording()
                        } label: {
                            Label(
                                viewModel.isTranscribing ? "Transcribing\u{2026}" : "Transcribe",
                                systemImage: viewModel.isTranscribing ? "hourglass" : "text.bubble.fill"
                            )
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(panelAccentSoft)
                        .disabled(!viewModel.canTranscribe)
                    }
                    .animation(.easeOut(duration: 0.22), value: viewModel.isReady)
                    .animation(.easeOut(duration: 0.18), value: viewModel.recordingPath)
                    .animation(.easeOut(duration: 0.18), value: viewModel.liveTranscript.isEmpty)
                    .animation(.easeOut(duration: 0.18), value: viewModel.transcriptText.isEmpty)
                    .animation(.easeOut(duration: 0.18), value: viewModel.polishedText.isEmpty)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                }

                // ── PINNED STATUS FOOTER ──
                Text(viewModel.statusFooter)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(panelMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(panelSurface.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(width: 408, height: 500)
        .foregroundStyle(panelText)
        .onAppear {
            viewModel.refreshRuntime()
        }
    }
}
