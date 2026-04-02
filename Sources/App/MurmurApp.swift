import AppKit
import Speech

// MARK: - Entry point

@main
struct MurmurApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - AppDelegate — orchestrates the entire dictation flow

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // ── Components ────────────────────────────────────────────────────────────
    private let menuBar = MenuBarController()
    private let settingsController = SettingsWindowController()
    private let fnMonitor = FnKeyMonitor()
    private let hotkeyManager = HotkeyManager()
    private let audioSession = AudioSession()
    private let transcriber = ColiTranscriber()
    private let transcriptEditPanel = TranscriptEditPanelController()

    private var liveSpeech: LiveSpeechRecognizer?
    private lazy var capsulePanel = CapsulePanel()

    // ── State machine ─────────────────────────────────────────────────────────
    private enum State { case idle, recording, transcribing, refining, editing, inserting }
    private var state: State = .idle
    private var processingTask: Task<Void, Never>?
    private var escLocalMonitor: Any?
    private var escGlobalMonitor: Any?

    // MARK: - Lifecycle

    func applicationWillTerminate(_ notification: Notification) {
        processingTask?.cancel()
        processingTask = nil

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
        PromptManager.shared.seedDefaultsIfNeeded()
        ConfigManager.shared.migrateIfNeeded()
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
        menuBar.setup()
        menuBar.onLanguageChanged = { [weak self] _ in
            // Force recreation of the recognizer with the new locale.
            self?.liveSpeech = nil
        }
        menuBar.onLLMToggled = { _ in /* state persisted by MenuBarController */ }
        menuBar.onSettingsRequested = { [weak self] in
            self?.settingsController.showSettings()
        }
    }

    private func setupFnKey() {
        fnMonitor.onFnDown = { [weak self] in
            Task { @MainActor in self?.startDictation() }
        }
        fnMonitor.onFnUp = { [weak self] in
            Task { @MainActor in self?.stopDictation() }
        }
        if !fnMonitor.start() {
            MurmurLogger.app.error("CGEvent tap failed; accessibility permission is required")
            showAccessibilityAlert()
        }
    }

    private func showAccessibilityAlert() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "Murmur 需要辅助功能权限来监听 Fn 键。\n\n请前往：系统设置 → 隐私与安全性 → 辅助功能\n然后添加并启用 Murmur。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开设置")
            alert.addButton(withTitle: "稍后")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }

            // Update menu bar to show warning
            self?.menuBar.setAccessibilityWarning(true)
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
            guard let self else { return }
            switch state {
            case .idle:      startDictation()
            case .recording: stopDictation()
            default:         break
            }
        }
        hotkeyManager.start()
    }

    private func setupEscMonitor() {
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                Task { @MainActor in self?.cancelDictation() }
                return nil
            }
            return event
        }
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.cancelDictation() }
            }
        }
    }

    private func showOnboardingIfNeeded() {
        let key = "hasShownOnboarding"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "Welcome to Murmur"
            alert.informativeText = "Hold Fn or press ⌥Space to start dictating.\nRelease to transcribe and paste.\nPress Esc anytime to cancel."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Got it")
            alert.runModal()
        }
    }

    // MARK: - Dictation flow

    private func startDictation() {
        guard state == .idle else { return }
        state = .recording

        // Wire audio level → capsule waveform.
        audioSession.levelSink = { [weak self] level in
            DispatchQueue.main.async { self?.capsulePanel.viewModel.audioLevel = level }
        }

        // Create (or reuse) a recognizer for the selected locale.
        let locale = menuBar.selectedLocale
        if liveSpeech == nil {
            liveSpeech = LiveSpeechRecognizer(locale: locale)
        }
        liveSpeech?.onPartialResult = { [weak self] text in
            guard let self else { return }
            capsulePanel.viewModel.text = text
            capsulePanel.updateWidth(for: text)
        }

        // Start recording.
        do {
            let path = try audioSession.startRecording()
            MurmurLogger.speech.info("Recording started: \(path, privacy: .public)")
        } catch {
            MurmurLogger.speech.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            showTransientCapsuleState(.error, text: error.localizedDescription, audioPath: nil)
            return
        }

        // Forward audio buffers to the recognizer.
        audioSession.bufferSink = { [weak self] buffer, time in
            self?.liveSpeech?.appendBuffer(buffer, at: time)
        }
        do { try liveSpeech?.start() } catch {
            MurmurLogger.speech.error("Live speech start failed: \(error.localizedDescription, privacy: .public)")
        }

        // Show capsule.
        capsulePanel.viewModel.state = .recording
        capsulePanel.viewModel.text = ""
        capsulePanel.viewModel.audioLevel = 0
        capsulePanel.showCapsule()
    }

    private func stopDictation() {
        guard state == .recording else { return }
        state = .transcribing

        let audioPath = audioSession.recordingPath
        let liveText = capsulePanel.viewModel.text

        audioSession.stopRecording()
        liveSpeech?.stop()

        capsulePanel.viewModel.state = .transcribing
        capsulePanel.viewModel.audioLevel = 0

        processingTask = Task {
            // ── Final transcription (prefer coli for accuracy) ────────────────
            var transcript = liveText
            let coliPath = AppPaths.coliHelperPath
            if ColiTranscriber.isAvailable(at: coliPath) {
                do {
                    let result = try await transcriber.transcribe(
                        filePath: audioPath, coliPath: coliPath
                    )
                    transcript = result.text
                } catch {
                    MurmurLogger.speech.error("Coli failed, falling back to live text: \(error.localizedDescription, privacy: .public)")
                }
            }

            guard !Task.isCancelled else {
                finish(audioPath: audioPath)
                return
            }

            // Nothing to paste?
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showTransientCapsuleState(.error, text: "No speech detected", audioPath: audioPath)
                return
            }

            // ── Optional LLM refinement ───────────────────────────────────────
            if menuBar.llmEnabled {
                state = .refining
                capsulePanel.viewModel.state = .refining
                capsulePanel.viewModel.text = "Refining…"

                do {
                    let dict = DictionaryManager.loadEntries()
                    transcript = try await LLMPolisher.shared.polish(
                        text: transcript, dictionary: dict
                    )
                } catch {
                    MurmurLogger.network.error("LLM polish failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            guard !Task.isCancelled else {
                finish(audioPath: audioPath)
                return
            }

            let transcriptAction = await resolveTranscriptAction(transcript)

            guard !Task.isCancelled else {
                finish(audioPath: audioPath)
                return
            }

            switch transcriptAction {
            case .cancel:
                showTransientCapsuleState(.cancelled, text: "Cancelled", audioPath: audioPath, hideAfter: 0.5)
                return
            case .copy(let editedText):
                TextInsertionService.copyToClipboard(editedText)
                showTransientCapsuleState(.success, text: "Copied to clipboard", audioPath: audioPath, hideAfter: 0.8)
                return
            case .insert(let editedText):
                transcript = editedText
            }

            // ── Text injection ────────────────────────────────────────────────
            state = .inserting
            switch await injectText(transcript) {
            case .success:
                finish(audioPath: audioPath)
            case .failure(let error):
                MurmurLogger.ui.error("Text insertion failed: \(error.localizedDescription, privacy: .public)")
                showTransientCapsuleState(.error, text: error.localizedDescription, audioPath: audioPath, hideAfter: 1.4)
            }
        }
    }

    private func resolveTranscriptAction(_ transcript: String) async -> TranscriptEditAction {
        guard ConfigManager.shared.editBeforePaste else {
            return .insert(transcript)
        }

        state = .editing
        capsulePanel.hideCapsule()
        return await transcriptEditPanel.edit(text: transcript)
    }

    private func cancelDictation() {
        guard state != .idle else { return }

        // Cancel any in-flight processing.
        processingTask?.cancel()
        processingTask = nil

        let audioPath = audioSession.recordingPath

        if state == .recording {
            audioSession.stopRecording()
            liveSpeech?.stop()
        }

        capsulePanel.viewModel.state = .cancelled
        capsulePanel.viewModel.text = ""
        capsulePanel.viewModel.audioLevel = 0
        showTransientCapsuleState(.cancelled, text: "Cancelled", audioPath: audioPath, hideAfter: 0.5)
    }

    // MARK: - Text injection (IME-safe, clipboard-restore)

    private func injectText(_ text: String) async -> Result<Void, Error> {
        let savedIME = IMEService.switchToASCII()
        let savedClipboard = TextInsertionService.saveClipboard()

        TextInsertionService.copyToClipboard(text)

        do {
            try TextInsertionService.simulatePaste()

            // Short delay so the paste event reaches the front app.
            try await Task.sleep(nanoseconds: 150_000_000)

            if let saved = savedClipboard {
                TextInsertionService.restoreClipboard(saved)
            }
            if let ime = savedIME {
                IMEService.restore(ime)
            }

            return .success(())
        } catch {
            if let ime = savedIME {
                IMEService.restore(ime)
            }
            return .failure(error)
        }
    }

    private func showTransientCapsuleState(
        _ capsuleState: CapsuleState,
        text: String,
        audioPath: String?,
        hideAfter delay: TimeInterval = 1.0
    ) {
        capsulePanel.viewModel.state = capsuleState
        capsulePanel.viewModel.text = text
        capsulePanel.viewModel.audioLevel = 0
        capsulePanel.updateWidth(for: text)

        if !capsulePanel.isVisible {
            capsulePanel.showCapsule()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.finish(audioPath: audioPath)
        }
    }

    // MARK: - Cleanup

    private func finish(audioPath: String?) {
        capsulePanel.hideCapsule()
        state = .idle
        processingTask = nil
        if let audioPath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
    }
}
