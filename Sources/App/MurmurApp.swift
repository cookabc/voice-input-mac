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
    private static let fnHoldDelayNanoseconds: UInt64 = 250_000_000

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
    private var fnHoldTask: Task<Void, Never>?
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
        fnHoldTask?.cancel()
        fnHoldTask = nil
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
        dictationCoordinator.menuBar = menuBar
        dictationCoordinator.selectedLocaleProvider = { [weak self] in
            self?.menuBar.selectedLocale ?? "zh-CN"
        }
        dictationCoordinator.llmEnabledProvider = { [weak self] in
            self?.menuBar.llmEnabled ?? true
        }
        menuBar.onLanguageChanged = { [weak self] _ in
            self?.dictationCoordinator.resetLiveSpeechRecognizer()
        }
        menuBar.onLLMToggled = { _ in /* state persisted by MenuBarController */ }
        menuBar.onSettingsRequested = { [weak self] in
            self?.settingsController.showSettings()
        }
        menuBar.onMenuOpened = { [weak self] in
            self?.refreshAccessibilityState()
        }
        settingsController.onEditBeforePasteChanged = { [weak self] _ in
            self?.menuBar.reloadEditBeforePaste()
        }
    }

    private func setupFnKey() {
        fnMonitor.onFnDown = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fnHoldTask?.cancel()

                guard self.dictationCoordinator.phase == .idle else { return }

                // Start recording after a brief hold to filter out accidental taps.
                self.fnHoldTask = Task { @MainActor [weak self] in
                    guard let self else { return }

                    do {
                        try await Task.sleep(nanoseconds: Self.fnHoldDelayNanoseconds)
                    } catch {
                        return
                    }

                    guard !Task.isCancelled, self.dictationCoordinator.phase == .idle else { return }
                    self.fnHoldTask = nil
                    self.dictationCoordinator.startDictation()
                }
            }
        }
        // Push-to-talk: release Fn → stop recording and begin transcription.
        fnMonitor.onFnUp = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fnHoldTask?.cancel()
                self.fnHoldTask = nil

                if self.dictationCoordinator.phase == .recording {
                    self.dictationCoordinator.stopDictation()
                }
            }
        }
        refreshAccessibilityState()

        // Retry tap when app re-activates (user may have just granted permission).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.menuBar.hasAccessibilityWarning else { return }
                self.refreshAccessibilityState()
            }
        }
    }

    private func refreshAccessibilityState() {
        guard TextInsertionService.isAccessibilityTrusted() else {
            fnMonitor.stop()
            menuBar.setAccessibilityWarning(true)

            MurmurLogger.app.error("CGEvent tap failed; accessibility permission is required")
            return
        }

        if fnMonitor.start() {
            menuBar.setAccessibilityWarning(false)
        } else {
            menuBar.setAccessibilityWarning(true)
            MurmurLogger.app.info("Accessibility is granted, but the event tap is still unavailable; keeping warning visible")
        }
    }

    private func showLaunchConfigurationAlert(for issue: LaunchConfigurationIssue) {
        noticePanel.show(
            title: issue.alertTitle,
            message: issue.alertMessage,
            style: .warning,
            primaryAction: NoticePanelAction(title: "Quit Murmur", role: .destructive) {
                NSApp.terminate(nil)
            }
        )
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
                Task { @MainActor in self?.handleEscapeKey() }
                return nil
            }
            return event
        }
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.handleEscapeKey() }
            }
        }
    }

    private func handleEscapeKey() {
        // Esc always means cancel, regardless of phase.
        guard dictationCoordinator.phase != .idle else { return }
        dictationCoordinator.cancelDictation()
    }

    private func showOnboardingIfNeeded() {
        let key = "hasShownOnboarding"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !menuBar.hasAccessibilityWarning else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.noticePanel.show(
                title: "Welcome to Murmur",
                message: "Hold Fn to dictate (release to finish), or press ⌥Space to toggle. Esc cancels.",
                style: .info,
                primaryAction: NoticePanelAction(title: "Got it", role: nil) {},
                secondaryAction: NoticePanelAction(title: "Open Settings", role: nil) { [weak self] in
                    self?.settingsController.showSettings()
                }
            )
        }
    }
}
