import AppKit
import Speech
import SwiftUI

// MARK: - Entry point

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MurmurMenuBarExtraContent(menuBar: appDelegate.menuBar)
        } label: {
            MurmurMenuBarExtraLabel(menuBar: appDelegate.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate — lifecycle and component wiring

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let configManager: any ConfigManaging
    private let promptManager: any PromptManaging
    private let polisher: LLMPolisher

    // ── Components ────────────────────────────────────────────────────────────
    let menuBar: MenuBarController
    private let settingsController: SettingsWindowController
    private let fnMonitor: FnKeyMonitor
    private let hotkeyManager: HotkeyManager
    private let noticePanel = NoticePanelController()

    private lazy var capsulePanel = CapsulePanel()
    private lazy var dictationCoordinator = DictationCoordinator(
        capsulePanel: capsulePanel,
        configManager: configManager,
        polisher: polisher
    )
    private var escLocalMonitor: Any?
    private var escGlobalMonitor: Any?

    override init() {
        let configManager = ConfigManager.shared
        let promptManager = PromptManager.shared
        let polisher = LLMPolisher(
            promptProvider: { text in
                (promptManager.systemPrompt, promptManager.renderUserPrompt(text: text))
            }
        )

        self.configManager = configManager
        self.promptManager = promptManager
        self.polisher = polisher
        self.menuBar = MenuBarController(configManager: configManager)
        self.settingsController = SettingsWindowController(configManager: configManager, polisher: polisher)
        self.fnMonitor = FnKeyMonitor()
        self.hotkeyManager = HotkeyManager()

        super.init()
    }

    // MARK: - Lifecycle

    func applicationWillTerminate(_ notification: Notification) {
        dictationCoordinator.prepareForTermination()

        // Remove ESC monitors to prevent memory leaks
        if let localMonitor = escLocalMonitor {
            NSEvent.removeMonitor(localMonitor)
            escLocalMonitor = nil
        }
        if let globalMonitor = escGlobalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            escGlobalMonitor = nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let launchIssue = LaunchConfigurationValidator.validate() {
            MurmurLogger.app.error("\(launchIssue.logMessage, privacy: .public)")
            showLaunchConfigurationAlert(for: launchIssue)
            return
        }

        // Prompt for Accessibility if needed (required for CGEvent tap + paste).
        TextInsertionService.promptAccessibility()

        // Request speech recognition permission.
        Task { await LiveSpeechRecognizer.requestAuthorization() }

        // Seed support files.
        DictionaryManager.ensureFileExists()
        promptManager.seedDefaultsIfNeeded()
        configManager.migrateIfNeeded()
        MurmurLogger.app.info("Murmur support directory: \(AppPaths.appSupportDirectory.path, privacy: .public)")

        setupMenuBar()
        setupFnKey()
        setupHotkey()
        setupEscMonitor()

        settingsController.hotkeyManager = hotkeyManager

        showOnboardingIfNeeded()
    }

    // MARK: - Setup helpers

    private func setupMenuBar() {
        dictationCoordinator.selectedLocaleProvider = { [weak self] in
            self?.menuBar.selectedLocale ?? "zh-CN"
        }
        dictationCoordinator.llmEnabledProvider = { [weak self] in
            self?.menuBar.llmEnabled ?? true
        }
        dictationCoordinator.runtimeStateSink = { [weak self] runtimeState in
            self?.menuBar.setRuntimeState(runtimeState)
        }
        menuBar.onLanguageChanged = { [weak self] _ in
            self?.dictationCoordinator.resetLiveSpeechRecognizer()
        }
        menuBar.onLLMToggled = { _ in /* state persisted by MenuBarController */ }
        menuBar.onSettingsRequested = { [weak self] in
            self?.settingsController.showSettings()
        }
    }

    private func setupFnKey() {
        fnMonitor.onFnDown = { [weak self] in
            Task { @MainActor in self?.dictationCoordinator.startDictation() }
        }
        fnMonitor.onFnUp = { [weak self] in
            Task { @MainActor in self?.dictationCoordinator.stopDictation() }
        }
        if !fnMonitor.start() {
            MurmurLogger.app.error("CGEvent tap failed; accessibility permission is required")
            showAccessibilityNotice()
        }
    }

    private func showAccessibilityNotice() {
        menuBar.setAccessibilityWarning(true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.noticePanel.show(
                title: "Accessibility Required",
                message: "Murmur needs Accessibility access to monitor Fn and paste text into the active app. You can grant access now or return later from the menu bar warning state.",
                style: .warning,
                primaryAction: NoticePanelAction(title: "Open Settings", role: nil) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                },
                secondaryAction: NoticePanelAction(title: "Later", role: .cancel) {}
            )
        }
    }

    private func showLaunchConfigurationAlert(for issue: LaunchConfigurationIssue) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = issue.alertTitle
        alert.informativeText = issue.alertMessage
        alert.alertStyle = .critical
        alert.addButton(withTitle: "退出")
        alert.runModal()

        NSApp.terminate(nil)
    }

    private func setupHotkey() {
        hotkeyManager.onTriggered = { [weak self] in
            self?.dictationCoordinator.handlePrimaryTrigger()
        }
        hotkeyManager.start()
    }

    private func setupEscMonitor() {
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                Task { @MainActor in self?.dictationCoordinator.cancelDictation() }
                return nil
            }
            return event
        }
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.dictationCoordinator.cancelDictation() }
            }
        }
    }

    private func showOnboardingIfNeeded() {
        let key = "hasShownOnboarding"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !menuBar.hasAccessibilityWarning else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.noticePanel.show(
                title: "Welcome to Murmur",
                message: "Hold Fn or press Option-Space to start dictating. Release to transcribe and paste, or press Esc anytime to cancel.",
                style: .info,
                primaryAction: NoticePanelAction(title: "Got it", role: nil) {},
                secondaryAction: NoticePanelAction(title: "Open Settings", role: nil) { [weak self] in
                    self?.settingsController.showSettings()
                }
            )
        }
    }
}
