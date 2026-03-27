import SwiftUI

struct ShellPanelView: View {
    @ObservedObject var viewModel: ShellViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showProviderConfig = false
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
        if viewModel.isRecordingActive { return panelDanger.opacity(0.85) }
        if viewModel.isReady { return Color(red: 0.82, green: 0.52, blue: 0.26) } // softer amber
        if viewModel.runtimeBadge == "Needs setup" { return Color(red: 0.75, green: 0.62, blue: 0.18) }
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
        if viewModel.compactMode {
            CompactFlowBar(
                viewModel: viewModel,
                danger: panelDanger,
                muted: panelMuted,
                textColor: panelText,
                background: panelBackground
            )
        } else {
        ZStack {
            // ── MAIN PANEL ──
            ZStack {
            LinearGradient(
                colors: [panelBackground, dark ? Color(red: 0.10, green: 0.16, blue: 0.17) : Color(red: 0.93, green: 0.94, blue: 0.93)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(panelAccent.opacity(dark ? 0.09 : 0.06))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: 130, y: -170)

            Circle()
                .fill(panelAccentSoft.opacity(dark ? 0.11 : 0.07))
                .frame(width: 180, height: 180)
                .blur(radius: 32)
                .offset(x: -140, y: 580)

            VStack(spacing: 0) {
                // ── PINNED HEADER ──
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Murmur")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Dictate & polish")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(panelMuted)
                        // Hotkey hint
                        if !viewModel.hotkeyDisplayString.isEmpty {
                            HStack(spacing: 4) {
                                Text(viewModel.hotkeyDisplayString)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(panelAccent)
                                Text("auto-flow")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(panelMuted)
                            }
                        }
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

                    // ── AUTO-FLOW BUTTON ──
                    Button {
                        viewModel.togglePanelAutoFlow()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: viewModel.isRecordingActive ? "stop.circle.fill" : "waveform")
                                .font(.system(size: 11, weight: .bold))
                            if !viewModel.isRecordingActive {
                                Text("Auto")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundStyle(viewModel.isRecordingActive ? panelDanger : panelAccent)
                        .padding(.horizontal, viewModel.isRecordingActive ? 8 : 10)
                        .padding(.vertical, 6)
                        .background(
                            (viewModel.isRecordingActive ? panelDanger : panelAccent).opacity(0.15),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.isReady && !viewModel.isRecordingActive)
                    .help(viewModel.isRecordingActive ? "Stop & paste" : "Record → polish → paste")
                    .animation(.easeInOut(duration: 0.15), value: viewModel.isRecordingActive)

                    Button {
                        viewModel.openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(panelAccent.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .background(panelAccent.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings")

                    Button {
                        viewModel.openHistory()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(panelAccent.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .background(panelAccent.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("History")

                    Button {
                        viewModel.onRequestQuit?()
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(panelDanger.opacity(0.75))
                            .frame(width: 26, height: 26)
                            .background(panelDanger.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Quit Murmur")

                    Button {
                        viewModel.onRequestDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(panelMuted)
                            .frame(width: 26, height: 26)
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
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.orange.opacity(0.9))
                                    Text(viewModel.runtimeBadge)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(panelText)
                                }
                                Text(viewModel.detail)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(panelMuted)
                                HStack(spacing: 8) {
                                    Button("Refresh") {
                                        viewModel.refreshRuntime()
                                    }
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .buttonStyle(.bordered)
                                    .tint(panelAccent)

                                    Button("Settings") {
                                        viewModel.openSettings()
                                    }
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .buttonStyle(.bordered)
                                    .tint(panelAccentSoft)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(panelSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // ── Diagnostics: compact when healthy, full card when issues ──
                        if !viewModel.llmHint.isEmpty || viewModel.flowStage == .failed || !viewModel.metrics.stages.isEmpty {
                            // Full diagnostics card (issues or post-run metrics)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: viewModel.llmHint.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(viewModel.llmHint.isEmpty ? Color.green.opacity(0.8) : Color.orange.opacity(0.9))
                                    Text(viewModel.llmLine)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(panelText)
                                        .lineLimit(2)
                                    Spacer()
                                    Button("Refresh") {
                                        Task { @MainActor in
                                            await viewModel.refreshLLMRuntime()
                                        }
                                    }
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(panelAccent)

                                    if !viewModel.llmHint.isEmpty {
                                        Button("Fix") {
                                            viewModel.openSettings()
                                        }
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .buttonStyle(.plain)
                                        .foregroundStyle(panelAccentSoft)
                                    }
                                }

                                if !viewModel.llmHint.isEmpty {
                                    Text(viewModel.llmHint)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(panelMuted)
                                }

                                HStack(spacing: 8) {
                                    Image(systemName: viewModel.flowStage == .failed ? "xmark.octagon.fill" : "dot.circle.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(viewModel.flowStage == .failed ? panelDanger : panelAccentSoft)
                                    Text(viewModel.flowStage.label)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(viewModel.flowStage == .failed ? panelDanger : panelAccentSoft)
                                    Text("·")
                                        .foregroundStyle(panelMuted.opacity(0.4))
                                    Text(viewModel.flowLine)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(panelText)
                                        .lineLimit(1)
                                    Spacer()
                                }

                                if !viewModel.flowHint.isEmpty {
                                    Text(viewModel.flowHint)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(panelMuted)
                                }

                                if !viewModel.metrics.stages.isEmpty {
                                    Text(viewModel.metrics.stageSummaryText)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(panelMuted.opacity(0.7))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(panelSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            // Compact status bar (healthy state)
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.green.opacity(0.8))
                                Text(viewModel.flowLine)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(panelText)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    Task { @MainActor in
                                        await viewModel.refreshLLMRuntime()
                                    }
                                } label: {
                                    Text("Refresh")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(panelAccent)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(panelSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // ── ASR / MODE / VAD — collapsible config strip ──
                        // Collapse during active recording/transcribing.
                        if !viewModel.isRecordingActive && !viewModel.isTranscribing {
                            VStack(alignment: .leading, spacing: 0) {
                                // Summary row (always visible)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showProviderConfig.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "waveform.badge.mic")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(panelAccentSoft)
                                        Text(viewModel.asrRegistry.activeProvider?.displayName ?? "ASR")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(panelAccent)
                                        Text("·")
                                            .foregroundStyle(panelMuted.opacity(0.4))
                                        Image(systemName: viewModel.commandMode.activeCommand?.icon ?? "text.badge.checkmark")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.62, green: 0.46, blue: 0.86))
                                        Text(viewModel.commandMode.activeCommand?.name ?? "Clean")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color(red: 0.62, green: 0.46, blue: 0.86))
                                        if ConfigManager.shared.config.vadEnabled {
                                            Text("·")
                                                .foregroundStyle(panelMuted.opacity(0.4))
                                            Text("VAD")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(panelAccentSoft)
                                        }
                                        Spacer()
                                        Image(systemName: showProviderConfig ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(panelMuted)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                // Expanded config (on demand)
                                if showProviderConfig {
                                    Rectangle()
                                        .fill(panelMuted.opacity(0.15))
                                        .frame(height: 1)
                                        .padding(.horizontal, 12)

                                    VStack(alignment: .leading, spacing: 14) {
                                        // ASR Provider
                                        VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 8) {
                                            Text("ASR")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(panelMuted)
                                            Spacer()
                                        }
                                        HStack(spacing: 6) {
                                            ForEach(viewModel.asrRegistry.providers, id: \.id) { provider in
                                                Button {
                                                    viewModel.asrRegistry.selectedID = provider.id
                                                } label: {
                                                    VStack(spacing: 2) {
                                                        Text(provider.displayName)
                                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                        Text(provider.subtitle)
                                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                                            .foregroundStyle(panelMuted)
                                                    }
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        provider.id == viewModel.asrRegistry.selectedID
                                                            ? panelAccent.opacity(0.18)
                                                            : panelSurfaceStrong.opacity(0.8),
                                                        in: Capsule()
                                                    )
                                                    .overlay(
                                                        provider.id == viewModel.asrRegistry.selectedID
                                                            ? Capsule().stroke(panelAccent.opacity(0.5), lineWidth: 1)
                                                            : nil
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundStyle(
                                                    provider.id == viewModel.asrRegistry.selectedID
                                                        ? panelAccent : panelText.opacity(0.7)
                                                )
                                            }
                                        }
                                        } // end ASR VStack

                                        // Command Mode
                                        VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 8) {
                                            Text("MODE")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(panelMuted)
                                            Spacer()
                                        }

                                        HStack(spacing: 6) {
                                            Button {
                                                viewModel.commandMode.clearCommand()
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "text.badge.checkmark")
                                                        .font(.system(size: 10, weight: .semibold))
                                                    Text("Clean")
                                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    viewModel.commandMode.activeCommand == nil
                                                        ? Color(red: 0.62, green: 0.46, blue: 0.86).opacity(0.18)
                                                        : panelSurfaceStrong.opacity(0.8),
                                                    in: Capsule()
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(
                                                viewModel.commandMode.activeCommand == nil
                                                    ? Color(red: 0.62, green: 0.46, blue: 0.86) : panelText.opacity(0.7)
                                            )

                                            ForEach(viewModel.commandMode.builtInCommands) { cmd in
                                                Button {
                                                    viewModel.commandMode.selectCommand(cmd)
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: cmd.icon)
                                                            .font(.system(size: 10, weight: .semibold))
                                                        Text(cmd.name)
                                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                            .lineLimit(1)
                                                            .fixedSize(horizontal: true, vertical: false)
                                                    }
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        viewModel.commandMode.activeCommand?.id == cmd.id
                                                            ? Color(red: 0.62, green: 0.46, blue: 0.86).opacity(0.18)
                                                            : panelSurfaceStrong.opacity(0.8),
                                                        in: Capsule()
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundStyle(
                                                    viewModel.commandMode.activeCommand?.id == cmd.id
                                                        ? Color(red: 0.62, green: 0.46, blue: 0.86) : panelText.opacity(0.7)
                                                )
                                            }
                                        }
                                        } // end MODE VStack

                                        // VAD Toggle
                                        HStack(spacing: 8) {
                                            Text("VAD")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(panelMuted)
                                            Text("(experimental)")
                                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                                .foregroundStyle(panelMuted.opacity(0.6))
                                            Spacer()
                                            Toggle("", isOn: Binding(
                                                get: { ConfigManager.shared.config.vadEnabled },
                                                set: { newVal in
                                                    var cfg = ConfigManager.shared.config
                                                    cfg.vadEnabled = newVal
                                                    ConfigManager.shared.saveConfig(cfg)
                                                }
                                            ))
                                            .toggleStyle(.switch)
                                            .controlSize(.mini)
                                            .labelsHidden()
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(panelSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } // end ASR/MODE/VAD collapse

                        // ── Unified Record / Clip card ──
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(viewModel.isRecordingActive
                                    ? panelDanger.opacity(dark ? 0.13 : 0.09)
                                    : panelSurface.opacity(dark ? 0.88 : 0.80))

                            if viewModel.isRecordingActive {
                                // ── Recording ──
                                VStack(spacing: 10) {
                                    WaveformBarsView(level: viewModel.micLevel, color: panelDanger)
                                    Text(viewModel.recordingTimeString)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(panelDanger.opacity(0.8))
                                    Button {
                                        viewModel.stopRecording()
                                    } label: {
                                        Label("Stop", systemImage: "stop.fill")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(panelDanger)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            } else if viewModel.isTranscribing {
                                // ── Transcribing ──
                                VStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.85)
                                    Text("Transcribing\u{2026}")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(panelMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            } else if !viewModel.recordingPath.isEmpty {
                                // ── Clip ready ──
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "waveform")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(panelAccentSoft)
                                            Text("Clip ready")
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(panelText)
                                        }
                                        Button {
                                            viewModel.toggleClipPlayback()
                                        } label: {
                                            Label(viewModel.isPlayingClip ? "Stop" : "Play",
                                                  systemImage: viewModel.isPlayingClip ? "stop.fill" : "play.fill")
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(panelAccentSoft)
                                    }
                                    Spacer()
                                    Button {
                                        viewModel.startRecording()
                                    } label: {
                                        Label("Record", systemImage: "mic.fill")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(heroTint)
                                    .disabled(!viewModel.canStartRecording)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            } else {
                                // ── Idle ──
                                Button {
                                    viewModel.startRecording()
                                } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundStyle(heroTint)
                                        Text("Record")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(panelText)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                }
                                .buttonStyle(.plain)
                                .disabled(!viewModel.canStartRecording)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 108)

                        if !viewModel.actionError.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(viewModel.actionError)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(dark ? Color(red: 1.0, green: 0.84, blue: 0.78) : Color(red: 0.60, green: 0.15, blue: 0.08))
                                    .textSelection(.enabled)

                                if !viewModel.recoveryActions.isEmpty {
                                    HStack(spacing: 8) {
                                        ForEach(viewModel.recoveryActions) { action in
                                            Button(action.title) {
                                                viewModel.performRecoveryAction(action)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .tint(panelAccentSoft)
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((dark ? Color(red: 0.33, green: 0.15, blue: 0.13) : Color(red: 0.98, green: 0.90, blue: 0.88)).opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        // ── Transcript + Polished card (always visible) ──
                        VStack(alignment: .leading, spacing: 0) {
                            // ── Transcript ──
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Transcript")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(panelMuted)
                                    Spacer()
                                    if !viewModel.transcriptText.isEmpty {
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
                                }

                                if viewModel.transcriptText.isEmpty {
                                    Text("Your transcription will appear here…")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(panelMuted.opacity(0.45))
                                        .frame(minHeight: 44, alignment: .topLeading)
                                } else {
                                    Text(viewModel.transcriptText)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(panelText)
                                        .textSelection(.enabled)
                                }

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
                                    .disabled(viewModel.transcriptText.isEmpty)

                                    Button {
                                        viewModel.toggleTTS()
                                    } label: {
                                        Label(viewModel.isSpeakingTTS ? "Stop" : "Listen",
                                              systemImage: viewModel.isSpeakingTTS ? "stop.fill" : "speaker.wave.2.fill")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(viewModel.isSpeakingTTS ? panelDanger : panelAccentSoft)
                                    .disabled(viewModel.transcriptText.isEmpty && viewModel.polishedText.isEmpty)

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

                            // ── Polished (always visible below divider) ──
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(viewModel.polishedText.isEmpty
                                    ? Color(red: 0.72, green: 0.58, blue: 0.94).opacity(0.4)
                                    : Color(red: 0.72, green: 0.58, blue: 0.94))

                                if viewModel.polishedText.isEmpty {
                                    Text("Polished result will appear here…")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(panelMuted.opacity(0.45))
                                        .frame(minHeight: 44, alignment: .topLeading)
                                } else {
                                    Text(viewModel.polishedText)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(panelText)
                                        .textSelection(.enabled)
                                }

                                Button {
                                    viewModel.copyPolished()
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                                .buttonStyle(.bordered)
                                .tint(Color(red: 0.62, green: 0.46, blue: 0.86))
                                .disabled(viewModel.polishedText.isEmpty)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 20,
                                    bottomTrailingRadius: 20,
                                    topTrailingRadius: 0,
                                    style: .continuous
                                )
                                .fill(Color(red: 0.62, green: 0.46, blue: 0.86).opacity(dark ? 0.10 : 0.06))
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .background(panelSurfaceStrong.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .animation(.easeOut(duration: 0.18), value: viewModel.recordingPath)
                    .animation(.easeOut(duration: 0.18), value: viewModel.isRecordingActive)
                    .animation(.easeOut(duration: 0.18), value: viewModel.isTranscribing)
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

        // ── HISTORY PANEL ──
        if viewModel.showHistory {
            HistoryView(onDismiss: { viewModel.closeHistory() })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal:   .move(edge: .trailing)
                ))
        }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(minWidth: 380, idealWidth: 408, maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(panelText)
        .animation(.easeInOut(duration: 0.25), value: viewModel.showSettings)
        .animation(.easeInOut(duration: 0.25), value: viewModel.showHistory)
        .onAppear {
            viewModel.refreshRuntime()
        }
        } // end else (compact mode)
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

/// Thin floating pill shown during hotkey auto-flow (recording → polish → paste).
private struct CompactFlowBar: View {
    @ObservedObject var viewModel: ShellViewModel
    let danger: Color
    let muted: Color
    let textColor: Color
    let background: Color
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }

    private var pillBg: Color {
        dark ? Color(white: 0.14).opacity(0.97) : Color(white: 0.96).opacity(0.97)
    }

    private var statusColor: Color {
        if viewModel.isRecordingActive { return danger }
        if viewModel.autoFlowStatus.hasPrefix("✓") { return Color(red: 0.28, green: 0.72, blue: 0.48) }
        return muted
    }

    var body: some View {
        HStack(spacing: 10) {
            if viewModel.isRecordingActive {
                WaveformBarsView(level: viewModel.micLevel, color: danger)
                    .frame(width: 40, height: 28)
            } else if viewModel.isTranscribing || viewModel.isPolishing {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(statusColor)
            }

            Text(viewModel.autoFlowStatus)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if viewModel.isRecordingActive {
                Text(viewModel.recordingTimeString)
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 320, height: 60)
        .background(pillBg)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
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
