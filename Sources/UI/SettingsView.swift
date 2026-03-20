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
                                    } else {
                                        SecureField("sk-\u{2026}", text: $apiKey)
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
                            presetChip("Ollama",
                                       url: "http://localhost:11434/v1",
                                       m: "llama3.2")
                        }
                    }

                    // ── INFO ──
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 13))
                            .foregroundStyle(muted)
                        Text("Your API key is stored in UserDefaults on this Mac only. It is sent exclusively to your configured Base URL endpoint.")
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
}
