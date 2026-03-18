import SwiftUI

struct ShellPanelView: View {
    @ObservedObject var viewModel: ShellViewModel

    private let panelBackground = Color(red: 0.08, green: 0.12, blue: 0.13)
    private let panelSurface = Color(red: 0.12, green: 0.18, blue: 0.18)
    private let panelSurfaceStrong = Color(red: 0.18, green: 0.24, blue: 0.23)
    private let panelText = Color(red: 0.95, green: 0.94, blue: 0.89)
    private let panelMuted = Color(red: 0.67, green: 0.73, blue: 0.70)
    private let panelAccent = Color(red: 0.90, green: 0.58, blue: 0.31)
    private let panelAccentSoft = Color(red: 0.31, green: 0.52, blue: 0.49)
    private let panelDanger = Color(red: 0.75, green: 0.36, blue: 0.27)

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
                colors: [panelBackground, Color(red: 0.10, green: 0.16, blue: 0.17)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(panelAccent.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 30)
                .offset(x: 130, y: -170)

            Circle()
                .fill(panelAccentSoft.opacity(0.22))
                .frame(width: 180, height: 180)
                .blur(radius: 24)
                .offset(x: -140, y: 170)

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice Input")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("On-device dictation")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(panelMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(viewModel.runtimeBadge)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(badgeTint.opacity(0.18), in: Capsule())
                        Text("Core \(viewModel.rustVersion)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(panelMuted)
                    }

                    Button {
                        viewModel.onRequestDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(panelMuted)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if !viewModel.isReady {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(panelText)
                            .lineLimit(2)
                        Text(viewModel.detail)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(panelMuted)
                            .lineSpacing(2)
                    }
                    .padding(16)
                    .background(panelSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(viewModel.primaryActionTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(panelText)

                    Text(viewModel.primaryActionSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(panelMuted)

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
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(heroTint)
                    .disabled(!viewModel.canStartRecording && !viewModel.canStopRecording)
                }
                .padding(16)
                .background(panelSurfaceStrong.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

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
                    }
                    .padding(14)
                    .background(panelSurface.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                if !viewModel.actionError.isEmpty {
                    Text(viewModel.actionError)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.78))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.33, green: 0.15, blue: 0.13).opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if !viewModel.transcriptText.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcript")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(panelMuted)

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
                        }
                    }
                    .padding(16)
                    .background(panelSurfaceStrong.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        actionButton(
                            title: viewModel.isTranscribing ? "Transcribing…" : "Transcribe",
                            systemImage: viewModel.isTranscribing ? "hourglass" : "text.bubble.fill",
                            tint: panelAccentSoft
                        ) {
                            viewModel.transcribeLatestRecording()
                        }
                        .disabled(!viewModel.canTranscribe)

                        actionButton(title: "Paste", systemImage: "arrow.up.doc.fill", prominent: true, tint: panelAccentSoft) {
                            viewModel.pasteTranscript()
                        }
                        .disabled(!viewModel.canPasteTranscript)
                    }

                    HStack(spacing: 10) {
                        actionButton(title: viewModel.diagnosticsExpanded ? "Hide status" : "Show status", systemImage: viewModel.diagnosticsExpanded ? "eye.slash" : "waveform.path.ecg", tint: panelAccentSoft) {
                            viewModel.toggleDiagnostics()
                        }

                        actionButton(title: "Refresh", systemImage: "arrow.clockwise", tint: panelAccentSoft) {
                            viewModel.refreshRuntime()
                        }
                    }
                }

                if viewModel.diagnosticsExpanded {
                    VStack(spacing: 10) {
                        diagnosticsRow(systemImage: "waveform", title: viewModel.ffmpegLine,
                                       alert: viewModel.ffmpegLine.contains("missing"))
                        diagnosticsRow(systemImage: "text.bubble", title: viewModel.coliLine,
                                       alert: viewModel.coliLine.contains("missing"))
                        diagnosticsRow(systemImage: "cpu", title: "Rust core \(viewModel.rustVersion)")
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if viewModel.diagnosticsExpanded {
                    Text(viewModel.diagnosticsSummary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(panelMuted)
                }
            }
            .animation(.easeOut(duration: 0.22), value: viewModel.isReady)
            .animation(.easeOut(duration: 0.18), value: viewModel.recordingPath)
            .animation(.easeOut(duration: 0.18), value: viewModel.diagnosticsExpanded)
            .padding(18)
            }  // end ScrollView
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(width: 408, height: 500)
        .foregroundStyle(panelText)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.refreshRuntime()
        }
    }

    @ViewBuilder
    private func diagnosticsRow(systemImage: String, title: String, alert: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 18)
                .foregroundStyle(alert ? panelDanger : panelAccentSoft)

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(alert ? panelDanger.opacity(0.90) : panelText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(alert ? panelDanger.opacity(0.10) : panelSurface.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func actionButton(title: String, systemImage: String, prominent: Bool = false, tint: Color, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(tint)
        }
    }
}
