import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ShellViewModel
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }

    private var bg: Color {
        dark ? Color(red: 0.08, green: 0.12, blue: 0.13)
             : Color(red: 0.96, green: 0.96, blue: 0.95)
    }
    private var surface: Color {
        dark ? Color(red: 0.12, green: 0.18, blue: 0.18)
             : Color(red: 0.92, green: 0.93, blue: 0.92)
    }
    private var surfaceStrong: Color {
        dark ? Color(red: 0.18, green: 0.24, blue: 0.23)
             : Color(red: 0.86, green: 0.88, blue: 0.87)
    }
    private var textColor: Color {
        dark ? Color(red: 0.95, green: 0.94, blue: 0.89)
             : Color(red: 0.12, green: 0.13, blue: 0.15)
    }
    private var muted: Color {
        dark ? Color(red: 0.67, green: 0.73, blue: 0.70)
             : Color(red: 0.42, green: 0.45, blue: 0.43)
    }
    private let accent = Color(red: 0.90, green: 0.58, blue: 0.31)

    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var showAPIKey = false
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any? = nil
    @State private var dictionaryCount = 0
    @State private var showAdvanced = false
    @FocusState private var focusedField: Field?

    private enum Field { case apiKey, baseURL, model }

    var body: some View {
        VStack(spacing: 0) {
            // ── HEADER ──
            HStack(alignment: .center) {
                Button {
                    save()
                    viewModel.closeSettings()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)

                Spacer()
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)

            // ── CONTENT ──
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {

                    // ── LLM POLISH ──
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("LLM POLISH")
                        VStack(spacing: 0) {
                            // API Key
                            HStack(spacing: 10) {
                                fieldLabel("API Key")
                                Group {
                                    if showAPIKey {
                                        TextField("sk-\u{2026}", text: $apiKey)
                                            .focused($focusedField, equals: .apiKey)
                                    } else {
                                        SecureField("sk-\u{2026}", text: $apiKey)
                                            .focused($focusedField, equals: .apiKey)
                                    }
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.plain)
                                .foregroundStyle(textColor)
                                Button { showAPIKey.toggle() } label: {
                                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                        .font(.system(size: 12))
                                        .foregroundStyle(muted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)

                            rowDivider

                            // Base URL
                            HStack(spacing: 10) {
                                fieldLabel("Base URL")
                                TextField("https://api.openai.com", text: $baseURL)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(textColor)
                                Text("/v1/…")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(muted.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)

                            rowDivider

                            // Model
                            HStack(spacing: 10) {
                                fieldLabel("Model")
                                TextField("gpt-4o-mini", text: $model)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(textColor)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                        .background(surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // Presets
                        sectionHeader("PRESETS")
                            .padding(.top, 4)

                        HStack(spacing: 8) {
                            presetChip("OpenAI",
                                       url: "https://api.openai.com",
                                       m: "gpt-4o-mini")
                            presetChip("Groq",
                                       url: "https://api.groq.com/openai",
                                       m: "llama-3.3-70b-versatile")
                            presetChip("Qwen",
                                       url: "http://localhost:11434/v1",
                                       m: "qwen2.5:7b")
                        }

                        sectionHeader("RUNTIME")
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: viewModel.llmHint.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(viewModel.llmHint.isEmpty ? Color.green.opacity(0.8) : Color.orange.opacity(0.9))
                                Text(viewModel.llmLine)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(textColor)
                                Spacer()
                                Button("Refresh") {
                                    Task { @MainActor in
                                        await viewModel.refreshLLMRuntime()
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent)
                                .buttonStyle(.plain)
                            }

                            if !viewModel.llmHint.isEmpty {
                                Text(viewModel.llmHint)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(muted)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // ── SPEECH ENGINE ──
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("SPEECH ENGINE")

                        VStack(spacing: 0) {
                            // ASR Provider
                            HStack(spacing: 10) {
                                fieldLabel("Engine")
                                Spacer()
                                HStack(spacing: 6) {
                                    ForEach(viewModel.asrRegistry.providers, id: \.id) { provider in
                                        Button {
                                            viewModel.asrRegistry.selectedID = provider.id
                                        } label: {
                                            VStack(spacing: 1) {
                                                Text(provider.displayName)
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                Text(provider.subtitle)
                                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                                    .foregroundStyle(muted)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                provider.id == viewModel.asrRegistry.selectedID
                                                    ? accent.opacity(0.18)
                                                    : surfaceStrong.opacity(0.8),
                                                in: Capsule()
                                            )
                                            .overlay(
                                                provider.id == viewModel.asrRegistry.selectedID
                                                    ? Capsule().stroke(accent.opacity(0.5), lineWidth: 1)
                                                    : nil
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(
                                            provider.id == viewModel.asrRegistry.selectedID
                                                ? accent : textColor.opacity(0.7)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)

                            rowDivider

                            // VAD Toggle
                            HStack(spacing: 10) {
                                fieldLabel("VAD")
                                Text("Voice activity detection")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(muted)
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                        .background(surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.system(size: 11))
                                .foregroundStyle(muted)
                            Text("SenseVoice supports Chinese, English, Japanese, Korean, and Cantonese. Whisper is English only. VAD (experimental) auto-detects speech boundaries.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(muted)
                                .lineSpacing(3)
                        }
                    }

                    // ── GLOBAL HOTKEY ──
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("GLOBAL HOTKEY")

                        HStack(spacing: 10) {
                            fieldLabel("Shortcut")
                            if isRecordingHotkey {
                                Text("Press shortcut…")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(accent)
                                    .transition(.opacity)
                            } else {
                                Text(viewModel.hotkeyDisplayString.isEmpty ? "—" : viewModel.hotkeyDisplayString)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(textColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(surfaceStrong.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                            }
                            Spacer()
                            Button(isRecordingHotkey ? "Cancel" : "Change") {
                                if isRecordingHotkey {
                                    stopHotkeyRecording()
                                } else {
                                    startHotkeyRecording()
                                }
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isRecordingHotkey ? muted : accent)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .animation(.easeInOut(duration: 0.15), value: isRecordingHotkey)

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 11))
                                .foregroundStyle(muted)
                            Text("Hold modifier keys (e.g. ⌘, ⌥, ⇧, ⌃) then press a key to set a new global shortcut. The shortcut fires anywhere — Murmur need not be focused.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(muted)
                                .lineSpacing(3)
                        }
                    }

                    // ── USER DICTIONARY ──
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("USER DICTIONARY")

                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                fieldLabel("File")
                                Text(DictionaryManager.dictionaryFilePath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(muted)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)

                            rowDivider

                            HStack(spacing: 10) {
                                fieldLabel("Terms")
                                Text("\(dictionaryCount) term\(dictionaryCount == 1 ? "" : "s")")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(textColor)
                                Spacer()
                                Button("Open in Finder") {
                                    DictionaryManager.ensureFileExists()
                                    NSWorkspace.shared.activateFileViewerSelecting(
                                        [URL(fileURLWithPath: DictionaryManager.dictionaryFilePath)]
                                    )
                                }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent)
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                        .background(surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "text.badge.checkmark")
                                .font(.system(size: 11))
                                .foregroundStyle(muted)
                            Text("One term per line. Lines starting with # are comments. Add domain-specific words to improve how the LLM corrects your transcription.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(muted)
                                .lineSpacing(3)
                        }
                    }

                    // ── ADVANCED ──
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                sectionHeader("ADVANCED")
                                Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(muted)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        if showAdvanced {
                            VStack(spacing: 0) {
                                // Config file
                                HStack(spacing: 10) {
                                    fieldLabel("Config")
                                    Text(ConfigManager.shared.configFilePath)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(muted)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Text(ConfigManager.shared.isUsingFile ? "Active" : "Defaults")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(ConfigManager.shared.isUsingFile ? Color.green.opacity(0.8) : muted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)

                                rowDivider

                                // Prompt directory
                                HStack(spacing: 10) {
                                    fieldLabel("Prompts")
                                    Text("~/.murmur/prompts/")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(muted)
                                    Spacer()
                                    Button("Open") {
                                        let url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + "/.murmur/prompts")
                                        NSWorkspace.shared.open(url)
                                    }
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(accent)
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)

                                rowDivider

                                // History DB
                                HStack(spacing: 10) {
                                    fieldLabel("History")
                                    Text("~/.murmur/history.db")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(muted)
                                    Spacer()
                                    let st = HistoryStore.shared.stats()
                                    Text("\(st.totalSessions) sessions")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(muted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            }
                            .background(surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundStyle(muted)
                                Text("Edit ~/.murmur/config.json to customise settings. Changes auto-reload. Edit prompts in ~/.murmur/prompts/ (system.txt / user.txt). Use {text} in user.txt as a placeholder for the transcript.")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(muted)
                                    .lineSpacing(3)
                            }
                        }
                    }

                    // ── INFO ──
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 13))
                            .foregroundStyle(muted)
                        Text("Your API key is stored in UserDefaults on this Mac only and is sent only to your configured Base URL endpoint when that endpoint requires one. Local models such as Ollama on localhost do not need an API key. Do not include /v1 in the Base URL — it is appended automatically.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(muted)
                            .lineSpacing(3)
                    }
                    .padding(12)
                    .background(surfaceStrong.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
        .onAppear {
            apiKey  = LLMPolisher.shared.apiKey  ?? ""
            baseURL = LLMPolisher.shared.baseURL
            model   = LLMPolisher.shared.model
            DictionaryManager.ensureFileExists()
            dictionaryCount = DictionaryManager.loadEntries().count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = .apiKey
            }
        }
        .onDisappear {
            stopHotkeyRecording()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(muted)
            .tracking(1.0)
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(muted)
            .frame(width: 68, alignment: .leading)
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.4)
            .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func presetChip(_ name: String, url: String, m: String) -> some View {
        Button {
            baseURL = url
            model   = m
        } label: {
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(surfaceStrong.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        LLMPolisher.shared.saveApiKey(apiKey)
        LLMPolisher.shared.saveBaseURL(baseURL)
        LLMPolisher.shared.saveModel(model)
    }

    private func startHotkeyRecording() {
        isRecordingHotkey = true
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Require at least one modifier key so bare printable keys aren’t captured.
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return event }
            viewModel.onUpdateHotkey?(mods, event.keyCode)
            DispatchQueue.main.async { self.stopHotkeyRecording() }
            return nil // consume the event
        }
    }

    private func stopHotkeyRecording() {
        isRecordingHotkey = false
        if let m = hotkeyMonitor {
            NSEvent.removeMonitor(m)
            hotkeyMonitor = nil
        }
    }
}
