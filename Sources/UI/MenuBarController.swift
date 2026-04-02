import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MenuBarController {

    enum RuntimeState: Equatable {
        case idle
        case recording
        case transcribing
        case refining
        case editing
        case cancelled(String)
        case success(String)
        case error(String)
    }

    @ObservationIgnored
    private let configManager: any ConfigManaging

    var hasAccessibilityWarning = false
    var runtimeState: RuntimeState = .idle

    @ObservationIgnored
    var onLanguageChanged: ((String) -> Void)?

    @ObservationIgnored
    var onLLMToggled: ((Bool) -> Void)?

    @ObservationIgnored
    var onSettingsRequested: (() -> Void)?

    init(configManager: any ConfigManaging = ConfigManager.shared) {
        self.configManager = configManager
    }

    func setAccessibilityWarning(_ warning: Bool) {
        hasAccessibilityWarning = warning
    }

    func setRuntimeState(_ state: RuntimeState) {
        runtimeState = state
    }

    var labelSymbolName: String {
        if hasAccessibilityWarning {
            return "mic.slash.fill"
        }

        switch runtimeState {
        case .idle:
            return "mic.fill"
        case .recording:
            return "waveform.and.mic"
        case .transcribing:
            return "text.bubble.fill"
        case .refining:
            return "sparkles"
        case .editing:
            return "square.and.pencil"
        case .cancelled:
            return "xmark.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var labelTintColor: Color {
        if hasAccessibilityWarning {
            return .orange
        }

        switch runtimeState {
        case .idle:
            return .primary
        case .recording:
            return .red
        case .transcribing:
            return .blue
        case .refining:
            return .purple
        case .editing:
            return .teal
        case .cancelled:
            return .secondary
        case .success:
            return .green
        case .error:
            return .yellow
        }
    }

    var labelAccessibilityDescription: String {
        if hasAccessibilityWarning {
            return "Murmur - Accessibility permission required"
        }

        switch runtimeState {
        case .idle:
            return "Murmur"
        case .recording:
            return "Murmur - Recording"
        case .transcribing:
            return "Murmur - Transcribing"
        case .refining:
            return "Murmur - Refining"
        case .editing:
            return "Murmur - Reviewing Transcript"
        case .cancelled:
            return "Murmur - Cancelled"
        case .success:
            return "Murmur - Success"
        case .error:
            return "Murmur - Error"
        }
    }

    static let supportedLanguages: [(id: String, name: String)] = [
        ("zh-CN", "中文（简体）"),
        ("zh-TW", "中文（繁體）"),
        ("en-US", "English"),
        ("ja",    "日本語"),
        ("ko",    "한국어"),
    ]

    // MARK: - Persisted state

    var selectedLocale: String {
        get { UserDefaults.standard.string(forKey: "asr_locale") ?? "zh-CN" }
        set {
            UserDefaults.standard.set(newValue, forKey: "asr_locale")
        }
    }

    var llmEnabled: Bool {
        get {
            // Default to ON if never set.
            UserDefaults.standard.object(forKey: "llm_refine_enabled") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "llm_refine_enabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "llm_refine_enabled")
        }
    }

    var editBeforePaste: Bool {
        get { configManager.editBeforePaste }
        set {
            configManager.saveEditBeforePaste(newValue)
        }
    }

    func updateSelectedLocale(_ locale: String) {
        selectedLocale = locale
        onLanguageChanged?(locale)
    }

    func updateLLMEnabled(_ enabled: Bool) {
        llmEnabled = enabled
        onLLMToggled?(enabled)
    }

    func openSettings() {
        onSettingsRequested?()
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private var runtimeStatusLine: String {
        switch runtimeState {
        case .idle:
            return "Status: Ready"
        case .recording:
            return "Status: Recording…"
        case .transcribing:
            return "Status: Transcribing…"
        case .refining:
            return "Status: Refining…"
        case .editing:
            return "Status: Reviewing transcript…"
        case .cancelled(let message):
            return "Status: \(message)"
        case .success(let message):
            return "Status: \(message)"
        case .error(let message):
            return "Status: \(message)"
        }
    }

    var runtimeStatusText: String {
        runtimeStatusLine
    }
}

struct MurmurMenuBarExtraContent: View {
    @Bindable var menuBar: MenuBarController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if menuBar.hasAccessibilityWarning {
                Button {
                    menuBar.openAccessibilitySettings()
                } label: {
                    Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }

            Text("Fn hold to dictate · Esc to cancel")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(menuBar.runtimeStatusText)
                .font(.subheadline.weight(.medium))
                .padding(.top, 2)

            Divider()
                .padding(.vertical, 10)

            Picker("Language", selection: Binding(
                get: { menuBar.selectedLocale },
                set: { menuBar.updateSelectedLocale($0) }
            )) {
                ForEach(MenuBarController.supportedLanguages, id: \.id) { language in
                    Text(language.name).tag(language.id)
                }
            }

            Toggle("LLM Refinement", isOn: Binding(
                get: { menuBar.llmEnabled },
                set: { menuBar.updateLLMEnabled($0) }
            ))

            Toggle("Review Before Paste", isOn: Binding(
                get: { menuBar.editBeforePaste },
                set: { menuBar.editBeforePaste = $0 }
            ))

            Divider()
                .padding(.vertical, 10)

            Button("Settings…") {
                menuBar.openSettings()
            }
            .keyboardShortcut(",")

            Button("Quit Murmur") {
                menuBar.quitApp()
            }
            .keyboardShortcut("q")
        }
        .toggleStyle(.switch)
        .frame(width: 280)
        .padding(14)
    }
}

struct MurmurMenuBarExtraLabel: View {
    @Bindable var menuBar: MenuBarController

    var body: some View {
        Image(systemName: menuBar.labelSymbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(menuBar.labelTintColor)
            .accessibilityLabel(menuBar.labelAccessibilityDescription)
    }
}
