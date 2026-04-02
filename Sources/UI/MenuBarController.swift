import AppKit

/// Manages the NSStatusItem + NSMenu in the menu bar.
/// Provides submenus for language selection, LLM toggle, and settings.
@MainActor
final class MenuBarController: NSObject {

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

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let configManager: any ConfigManaging
    private var hasAccessibilityWarning = false
    private var runtimeState: RuntimeState = .idle

    var onLanguageChanged: ((String) -> Void)?
    var onLLMToggled: ((Bool) -> Void)?
    var onSettingsRequested: (() -> Void)?

    init(configManager: any ConfigManaging = ConfigManager.shared) {
        self.configManager = configManager
        super.init()
    }

    func setAccessibilityWarning(_ warning: Bool) {
        hasAccessibilityWarning = warning
        updateStatusIcon()
        rebuildMenu()
    }

    func setRuntimeState(_ state: RuntimeState) {
        runtimeState = state
        updateStatusIcon()
        rebuildMenu()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)

        if hasAccessibilityWarning {
            button.image = NSImage(
                systemSymbolName: "mic.slash.fill",
                accessibilityDescription: "Murmur - 需要权限"
            )?.withSymbolConfiguration(configuration)
            button.contentTintColor = .systemOrange
            return
        }

        let symbolName: String
        let accessibilityDescription: String
        let tintColor: NSColor?

        switch runtimeState {
        case .idle:
            symbolName = "mic.fill"
            accessibilityDescription = "Murmur"
            tintColor = nil
        case .recording:
            symbolName = "waveform.and.mic"
            accessibilityDescription = "Murmur - Recording"
            tintColor = .systemRed
        case .transcribing:
            symbolName = "text.bubble.fill"
            accessibilityDescription = "Murmur - Transcribing"
            tintColor = .systemBlue
        case .refining:
            symbolName = "sparkles"
            accessibilityDescription = "Murmur - Refining"
            tintColor = .systemPurple
        case .editing:
            symbolName = "square.and.pencil"
            accessibilityDescription = "Murmur - Reviewing Transcript"
            tintColor = .systemTeal
        case .cancelled:
            symbolName = "xmark.circle.fill"
            accessibilityDescription = "Murmur - Cancelled"
            tintColor = .secondaryLabelColor
        case .success:
            symbolName = "checkmark.circle.fill"
            accessibilityDescription = "Murmur - Success"
            tintColor = .systemGreen
        case .error:
            symbolName = "exclamationmark.triangle.fill"
            accessibilityDescription = "Murmur - Error"
            tintColor = .systemYellow
        }

        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(configuration)
        button.contentTintColor = tintColor
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
            rebuildMenu()
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
            rebuildMenu()
        }
    }

    var editBeforePaste: Bool {
        get { configManager.editBeforePaste }
        set {
            configManager.saveEditBeforePaste(newValue)
            rebuildMenu()
        }
    }

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        rebuildMenu()
        statusItem?.menu = menu
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        menu.removeAllItems()

        // ── Accessibility Warning ──
        if hasAccessibilityWarning {
            let warningItem = NSMenuItem(
                title: "⚠️ 需要辅助功能权限",
                action: #selector(openAccessibilitySettings(_:)),
                keyEquivalent: ""
            )
            warningItem.target = self
            menu.addItem(warningItem)
            menu.addItem(.separator())
        }

        // ── Hint ──
        let hintItem = NSMenuItem(title: "Fn hold to dictate · Esc to cancel", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        let runtimeItem = NSMenuItem(title: runtimeStatusLine, action: nil, keyEquivalent: "")
        runtimeItem.isEnabled = false
        menu.addItem(runtimeItem)
        menu.addItem(.separator())

        // ── Language ──
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in Self.supportedLanguages {
            let item = NSMenuItem(
                title: lang.name,
                action: #selector(languageSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = lang.id
            item.state = lang.id == selectedLocale ? .on : .off
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(.separator())

        // ── LLM Refinement ──
        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()

        let enableItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleLLM(_:)),
            keyEquivalent: ""
        )
        enableItem.target = self
        enableItem.state = llmEnabled ? .on : .off
        llmMenu.addItem(enableItem)

        llmItem.submenu = llmMenu
        menu.addItem(llmItem)

        let reviewItem = NSMenuItem(
            title: "Review Before Paste",
            action: #selector(toggleEditBeforePaste(_:)),
            keyEquivalent: ""
        )
        reviewItem.target = self
        reviewItem.state = editBeforePaste ? .on : .off
        menu.addItem(reviewItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // ── Quit ──
        let quitItem = NSMenuItem(
            title: "Quit Murmur",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func languageSelected(_ sender: NSMenuItem) {
        guard let langId = sender.representedObject as? String else { return }
        selectedLocale = langId
        onLanguageChanged?(langId)
    }

    @objc private func toggleLLM(_ sender: NSMenuItem) {
        llmEnabled.toggle()
        onLLMToggled?(llmEnabled)
    }

    @objc private func toggleEditBeforePaste(_ sender: NSMenuItem) {
        editBeforePaste.toggle()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        onSettingsRequested?()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings(_ sender: NSMenuItem) {
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
}
