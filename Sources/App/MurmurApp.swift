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

    private var liveSpeech: LiveSpeechRecognizer?
    private lazy var capsulePanel = CapsulePanel()

    // ── State machine ─────────────────────────────────────────────────────────
    private enum State { case idle, recording, transcribing, refining, inserting }
    private var state: State = .idle
    private var processingTask: Task<Void, Never>?
    private var escLocalMonitor: Any?
    private var escGlobalMonitor: Any?

    // MARK: - Lifecycle

    func applicationWillTerminate(_ notification: Notification) {
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

        // Prompt for Accessibility if needed (required for CGEvent tap + paste).
        TextInsertionService.promptAccessibility()

        // Request speech recognition permission.
        Task { await LiveSpeechRecognizer.requestAuthorization() }

        // Seed support files.
        DictionaryManager.ensureFileExists()
        PromptManager.shared.seedDefaultsIfNeeded()
        ConfigManager.shared.migrateIfNeeded()

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
            fputs("[Murmur] CGEvent tap failed — grant Accessibility in System Settings.\n", stderr)
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
            fputs("[Murmur] Recording → \(path)\n", stderr)
        } catch {
            fputs("[Murmur] Recording failed: \(error.localizedDescription)\n", stderr)
            state = .idle
            return
        }

        // Forward audio buffers to the recognizer.
        audioSession.bufferSink = { [weak self] buffer, time in
            self?.liveSpeech?.appendBuffer(buffer, at: time)
        }
        do { try liveSpeech?.start() } catch {
            fputs("[Murmur] Live speech start failed: \(error.localizedDescription)\n", stderr)
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
                    fputs("[Murmur] Coli failed, using live text: \(error.localizedDescription)\n", stderr)
                }
            }

            guard !Task.isCancelled else {
                finish(audioPath: audioPath)
                return
            }

            // Nothing to paste?
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                finish(audioPath: audioPath)
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
                    fputs("[Murmur] LLM polish failed: \(error.localizedDescription)\n", stderr)
                }
            }

            guard !Task.isCancelled else {
                finish(audioPath: audioPath)
                return
            }

            // ── Text injection ────────────────────────────────────────────────
            state = .inserting
            await injectText(transcript)

            finish(audioPath: audioPath)
        }
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

        // Brief flash of "Cancelled" then hide.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.finish(audioPath: audioPath)
        }
    }

    // MARK: - Text injection (IME-safe, clipboard-restore)

    private func injectText(_ text: String) async {
        let savedIME = IMEService.switchToASCII()
        let savedClipboard = TextInsertionService.saveClipboard()

        TextInsertionService.copyToClipboard(text)
        try? TextInsertionService.simulatePaste()

        // Short delay so the paste event reaches the front app.
        try? await Task.sleep(nanoseconds: 150_000_000)

        if let saved = savedClipboard {
            TextInsertionService.restoreClipboard(saved)
        }
        if let ime = savedIME {
            IMEService.restore(ime)
        }
    }

    // MARK: - Cleanup

    private func finish(audioPath: String) {
        capsulePanel.hideCapsule()
        state = .idle
        try? FileManager.default.removeItem(atPath: audioPath)
    }
}
