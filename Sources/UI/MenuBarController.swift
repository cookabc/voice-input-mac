import AppKit

/// Manages the NSStatusItem + NSMenu in the menu bar.
/// Provides submenus for language selection, LLM toggle, and settings.
@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    var onLanguageChanged: ((String) -> Void)?
    var onLLMToggled: ((Bool) -> Void)?
    var onSettingsRequested: (() -> Void)?

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

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "Murmur"
            )
        }
        rebuildMenu()
        statusItem?.menu = menu
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        menu.removeAllItems()

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

        llmMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        llmItem.submenu = llmMenu
        menu.addItem(llmItem)

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

    @objc private func openSettings(_ sender: NSMenuItem) {
        onSettingsRequested?()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
