import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MenuBarController {
    @ObservationIgnored
    private let configManager: any ConfigManaging

    @ObservationIgnored
    private var suppressEditBeforePastePersistence = false

    var hasAccessibilityWarning = false
    var phase: DictationPhase = .idle

    @ObservationIgnored
    var onLanguageChanged: ((String) -> Void)?

    @ObservationIgnored
    var onLLMToggled: ((Bool) -> Void)?

    @ObservationIgnored
    var onSettingsRequested: (() -> Void)?

    @ObservationIgnored
    var onMenuOpened: (() -> Void)?

    init(configManager: any ConfigManaging = ConfigManager.shared) {
        self.configManager = configManager
        self.editBeforePaste = configManager.editBeforePaste
    }

    func setAccessibilityWarning(_ warning: Bool) {
        hasAccessibilityWarning = warning
    }

    func setPhase(_ phase: DictationPhase) {
        self.phase = phase
    }

    var labelSymbolName: String {
        if hasAccessibilityWarning {
            return "mic.slash.fill"
        }
        return phase.menuBarSymbol
    }

    var labelTintColor: Color {
        if hasAccessibilityWarning {
            return MurmurDesignTokens.Colors.warning
        }
        return phase.menuBarTint
    }

    var labelAccessibilityDescription: String {
        if hasAccessibilityWarning {
            return String(localized: "Murmur - Accessibility permission required")
        }
        return phase.menuBarAccessibilityLabel
    }

    static let supportedLanguages: [(id: String, name: String)] = [
        ("zh-CN", "中文（简体）"),
        ("zh-TW", "中文（繁體）"),
        ("en-US", "English"),
        ("ja", "日本語"),
        ("ko", "한국어")
    ]

    // MARK: - Persisted state

    var selectedLocale: String = UserDefaults.standard.string(forKey: "asr_locale") ?? "zh-CN" {
        didSet { UserDefaults.standard.set(selectedLocale, forKey: "asr_locale") }
    }

    var llmEnabled: Bool = {
        UserDefaults.standard.object(forKey: "llm_refine_enabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "llm_refine_enabled")
    }() {
        didSet { UserDefaults.standard.set(llmEnabled, forKey: "llm_refine_enabled") }
    }

    var editBeforePaste: Bool = false {
        didSet {
            guard !suppressEditBeforePastePersistence else { return }
            configManager.saveEditBeforePaste(editBeforePaste)
        }
    }

    func reloadEditBeforePaste() {
        suppressEditBeforePastePersistence = true
        defer { suppressEditBeforePastePersistence = false }
        editBeforePaste = configManager.editBeforePaste
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

    func notifyMenuOpened() {
        onMenuOpened?()
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    func requestAccessibilityAccess() {
        if !TextInsertionService.isAccessibilityTrusted() {
            TextInsertionService.promptAccessibility()
        }

        if let url = URL(string: NoticePanelAction.PrivacyPane.accessibility.urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private var runtimeStatusLine: String {
        phase.menuBarStatusLine
    }

    var runtimeStatusText: String {
        runtimeStatusLine
    }
}

struct MurmurMenuBarExtraContent: View {
    @Bindable var menuBar: MenuBarController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Accessibility warning ──────────────────────────────
            if menuBar.hasAccessibilityWarning {
                VStack(alignment: .leading, spacing: 10) {
                    Label(String(localized: "Accessibility permission required"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MurmurDesignTokens.Colors.warning)

                    Text(String(localized: "Request access, then enable Murmur in System Settings for Fn monitoring and auto-paste."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        menuBar.requestAccessibilityAccess()
                    } label: {
                        Label(String(localized: "Grant Accessibility Access"), systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(MurmurDesignTokens.Colors.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // ── Status header ─────────────────────────────────────
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(menuBar.labelTintColor.opacity(0.12))
                    Image(systemName: menuBar.labelSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(menuBar.labelTintColor)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Murmur")
                        .font(.system(size: 14, weight: .semibold))
                    Text(menuBar.runtimeStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(String(localized: "Hold Fn to dictate · Esc to cancel"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            // ── Controls card ─────────────────────────────────────
            VStack(spacing: 0) {
                // Language
                MenuBarRow {
                    Image(systemName: "globe")
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Language"))
                    Spacer(minLength: 8)
                    Picker("", selection: Binding(
                        get: { menuBar.selectedLocale },
                        set: { menuBar.updateSelectedLocale($0) }
                    )) {
                        ForEach(MenuBarController.supportedLanguages, id: \.id) { lang in
                            Text(lang.name).tag(lang.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.menuBarLanguagePicker)
                }

                Divider().padding(.leading, 40)

                // LLM Refinement
                MenuBarRow {
                    Image(systemName: "sparkles")
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "LLM Refinement"))
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { menuBar.llmEnabled },
                        set: { menuBar.updateLLMEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityIdentifier(AccessibilityID.menuBarLLMToggle)
                }

                Divider().padding(.leading, 40)

                // Review Before Paste
                MenuBarRow {
                    Image(systemName: "pencil.and.list.clipboard")
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Review Before Paste"))
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { menuBar.editBeforePaste },
                        set: { menuBar.editBeforePaste = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityIdentifier(AccessibilityID.menuBarEditToggle)
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // ── Actions card ──────────────────────────────────────
            VStack(spacing: 0) {
                MenuBarRow {
                    Image(systemName: "gearshape")
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Settings…")) {
                        menuBar.openSettings()
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(",")
                    Spacer()
                    Text("⌘,")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Divider().padding(.leading, 40)

                MenuBarRow {
                    Image(systemName: "power")
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Quit Murmur")) {
                        menuBar.quitApp()
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("q")
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .font(.system(size: 13))
        .frame(width: 280)
        .padding(12)
        .onAppear {
            menuBar.notifyMenuOpened()
        }
    }
}

/// Justified row: icon + label on the left, control on the right.
private struct MenuBarRow<Content: View>: View {
    @State private var isHovered = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            isHovered = hovering
        }
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
