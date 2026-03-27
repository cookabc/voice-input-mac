import AppKit
import AVFoundation
import Foundation

@MainActor
final class ShellViewModel: ObservableObject {
    enum FlowStage: String {
        case idle
        case recording
        case transcribing
        case polishing
        case readyToPaste
        case failed

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .recording: return "Recording"
            case .transcribing: return "Transcribing"
            case .polishing: return "Polishing"
            case .readyToPaste: return "Ready"
            case .failed: return "Failed"
            }
        }
    }

    enum RecoveryAction: String, Identifiable {
        case refreshRuntime
        case openSettings
        case retryTranscribe
        case retryPolish
        case retryPaste
        case startRecording

        var id: String { rawValue }

        var title: String {
            switch self {
            case .refreshRuntime: return "Refresh Runtime"
            case .openSettings: return "Open Settings"
            case .retryTranscribe: return "Retry Transcription"
            case .retryPolish: return "Retry Polish"
            case .retryPaste: return "Retry Paste"
            case .startRecording: return "Start Recording"
            }
        }
    }

    var onRequestDismiss: (() -> Void)?
    var onRequestQuit: (() -> Void)?
    var onRequestFocus: (() -> Void)?
    /// Called when an auto-flow cycle completes (after paste or on failure).
    var onAutoFlowComplete: (() -> Void)?
    /// Set by PanelController; called when the user picks a new shortcut in Settings.
    var onUpdateHotkey: ((NSEvent.ModifierFlags, UInt16) -> Void)?
    /// Human-readable hotkey string (e.g. "⌥Space"), kept in sync by PanelController.
    @Published var hotkeyDisplayString: String = ""

    @Published var title = "Murmur"
    @Published var detail = "Initializing transcription engine…"
    @Published var runtimeBadge = "Checking"
    @Published var coliLine = "Transcription engine checking…"
    @Published var llmLine = "LLM runtime unresolved"
    @Published var llmHint = ""
    @Published var recordingLine = "Idle"
    @Published var recordingPath = ""
    @Published var actionError = ""
    @Published var recoveryActions: [RecoveryAction] = []
    @Published var flowStage: FlowStage = .idle
    @Published var flowLine: String = "Idle"
    @Published var flowHint: String = ""
    @Published var transcriptText = ""
    @Published var transcriptMeta = ""
    @Published var isTranscribing = false
    @Published var isPlayingClip = false
    @Published var liveTranscript = ""
    @Published var isPolishing = false
    @Published var polishedText = ""
    @Published var showSettings = false
    @Published var showHistory = false
    @Published var recordingElapsed = 0
    @Published var micLevel: Float = 0
    /// True while an auto-flow (hotkey-initiated) cycle is running.
    @Published var isAutoFlow: Bool = false
    /// True while the compact overlay pill is the active UI mode.
    @Published var compactMode: Bool = false
    /// Brief human-readable status shown in the compact pill.
    @Published var autoFlowStatus: String = ""
    /// True while TTS is reading aloud for proofing.
    @Published var isSpeakingTTS: Bool = false
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private let tts = TextToSpeechService.shared
    let metrics = FlowMetrics()
    private let history = HistoryStore.shared
    let asrRegistry = ASRProviderRegistry.shared
    let commandMode = CommandModeManager.shared

    private let core = VoiceCoreService()

    var isReady: Bool { runtimeBadge == "Ready" }
    var isRecordingActive: Bool { recordingLine == "Recording live" }

    // MARK: - Hotkey / Auto-flow

    /// Called by `HotkeyManager` each time the global shortcut fires.
    /// First press → start recording in compact pill; second press → stop.
    func handleHotkey() {
        if isRecordingActive {
            stopRecording()
        } else if canStartRecording {
            isAutoFlow = true
            compactMode = true
            autoFlowStatus = "Listening…"
            startRecording()
        }
    }

    /// Called by the in-panel Auto button — stays in the full panel, no compact pill.
    func togglePanelAutoFlow() {
        if isRecordingActive {
            stopRecording()
        } else if canStartRecording {
            isAutoFlow = true
            // Do NOT set compactMode — keep the full panel open so stop is accessible.
            autoFlowStatus = "Listening…"
            startRecording()
        }
    }

    private func finishAutoFlow(text: String) {
        guard !text.isEmpty else {
            isAutoFlow = false
            compactMode = false
            setFlowStage(.idle, line: "Auto-flow finished")
            onAutoFlowComplete?()
            return
        }

        TextInsertionService.copyToClipboard(text)

        guard TextInsertionService.isAccessibilityTrusted() else {
            TextInsertionService.promptAccessibility()
            autoFlowStatus = "Copied (no Accessibility)"
            setFlowStage(.readyToPaste, line: "Copied, awaiting paste permission")
            isAutoFlow = false
            compactMode = false
            onAutoFlowComplete?()
            return
        }

        autoFlowStatus = "Pasting…"
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            try? TextInsertionService.simulatePaste()
            await MainActor.run {
                self.autoFlowStatus = "✓ Done"
                self.setFlowStage(.readyToPaste, line: "Auto-flow done")
                self.isAutoFlow = false
                // Brief pause so user sees "✓ Done" before pill disappears.
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    await MainActor.run {
                        self.compactMode = false
                        self.onAutoFlowComplete?()
                    }
                }
            }
        }
    }
    var canStartRecording: Bool { isReady && !isRecordingActive }
    var canStopRecording: Bool { isRecordingActive }
    var canTranscribe: Bool { !recordingPath.isEmpty && !isRecordingActive && !isTranscribing }
    var canPasteTranscript: Bool { !transcriptText.isEmpty }
    var canPolish: Bool { !transcriptText.isEmpty && !isPolishing && !isTranscribing }

    var statusFooter: String {
        coliLine.contains("ready") ? "✓ ASR" : "✗ ASR"
    }

    var recordingTimeString: String {
        let m = recordingElapsed / 60
        let s = recordingElapsed % 60
        return String(format: "%d:%02d", m, s)
    }

    func refreshRuntime() {
        Task { @MainActor in
            // Ensure config file exists for new users.
            ConfigManager.shared.migrateIfNeeded()
            PromptManager.shared.seedDefaultsIfNeeded()
            // Await permissions so the recognizer is authorized before the first recording.
            await core.requestPermissions()

            let coliExists = core.checkColiAvailable()
            runtimeBadge = coliExists ? "Ready" : "Needs setup"

            if coliExists {
                title = "Ready to dictate"
                detail = "Record a clip, then transcribe and paste it into any app."
            } else {
                title = "Setup required"
                detail = "Transcription engine not found. See setup instructions."
            }

            coliLine = statusLine(name: "Transcription", path: AppPaths.coliHelperPath, available: coliExists)
            await self.refreshLLMRuntime()
            recordingLine = core.isRecording ? "Recording live" : "Ready to record"
            if core.isRecording {
                setFlowStage(.recording, line: "Recording live")
            } else {
                setFlowStage(.idle, line: "Ready to record")
            }
            clearActionError()
        }
    }

    func refreshLLMRuntime() async {
        let probe = await LLMPolisher.shared.runtimeProbe()
        llmLine = probe.line
        llmHint = probe.actionHint ?? ""
    }

    func startRecording() {
        guard canStartRecording else {
            if isReady {
                setActionError("Recording is already running.", markFailure: false)
            } else {
                setActionError("Runtime is not ready for recording yet.", recoveryActions: [.refreshRuntime])
            }
            return
        }

        stopClipPlayback()
        stopTTS()
        // Clean up previous recording file before starting a new one.
        cleanupRecordingFile()

        do {
            let path = try core.startRecording()
            // Update recording state immediately — must happen before startLiveTranscription
            // so a live-ASR failure never leaves the UI in a zombie "Start failed" state.
            recordingPath = path
            recordingLine = "Recording live"
            clearActionError()
            transcriptText = ""
            transcriptMeta = ""
            liveTranscript = ""
            polishedText = ""
            setFlowStage(.recording, line: "Recording live")
        } catch {
            setActionError(error.localizedDescription, recoveryActions: [.startRecording])
            recordingLine = "Start failed"
            return
        }

        // Wire mic-level callback for waveform visualization (smoothed, main-actor safe).
        core.levelCallback = { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Fast attack, slow decay for smooth animation.
                let alpha: Float = level > self.micLevel ? 0.7 : 0.25
                self.micLevel = alpha * level + (1 - alpha) * self.micLevel
            }
        }
        // Start elapsed recording timer.
        recordingElapsed = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordingElapsed += 1 }
        }
        // Note: Live ASR (SFSpeechRecognizer) not used — coli provides better accuracy after recording.
    }

    func stopRecording() {
        guard canStopRecording else {
            setActionError("There is no active recording to stop.", recoveryActions: [.startRecording], markFailure: false)
            return
        }

        recordingTimer?.invalidate()
        recordingTimer = nil
        core.levelCallback = nil
        micLevel = 0
        core.stopRecording()
        recordingLine = "Recorded"
        setFlowStage(.transcribing, line: "Processing recording")
        clearActionError()
        if isAutoFlow { autoFlowStatus = "Transcribing…" }
        transcribeLatestRecording()
    }

    func transcribeLatestRecording() {
        guard canTranscribe else { return }

        isTranscribing = true
        setFlowStage(.transcribing, line: "Transcribing clip")
        clearActionError()
        let path = recordingPath
        let vm = self

        Task.detached(priority: .userInitiated) {
            do {
                let result = try await vm.core.transcribeAudio(at: path)
                let text = result.text
                var metaParts = [String]()
                if let lang = result.lang, !lang.isEmpty {
                                    // Strip whisper token formatting e.g. "<|zh|>" → "zh"
                                    let cleanLang = lang
                                        .replacingOccurrences(of: "<|", with: "")
                                        .replacingOccurrences(of: "|", with: "")
                                        .replacingOccurrences(of: ">", with: "")
                                        .trimmingCharacters(in: .whitespaces)
                                    metaParts.append("lang: \(cleanLang)")
                                }
                if let dur = result.duration { metaParts.append(String(format: "audio: %.1fs", dur)) }
                let meta = metaParts.joined(separator: "  |  ")
                await MainActor.run {
                    vm.liveTranscript = ""
                    vm.transcriptText = text
                    vm.transcriptMeta = meta
                    vm.isTranscribing = false
                    vm.setFlowStage(.readyToPaste, line: "Transcript ready")
                    vm.clearActionError()
                    // Auto-flow: chain straight to polish if transcript has real content.
                    if vm.isAutoFlow {
                        // Require at least 4 words to justify an LLM call.
                        let wordCount = text.split(whereSeparator: \.isWhitespace).count
                        let hasContent = wordCount >= 4
                        let canPolishLocally = !LLMPolisher.shared.requiresAPIKey || LLMPolisher.shared.apiKey != nil
                        if canPolishLocally && hasContent {
                            vm.autoFlowStatus = "Polishing…"
                            vm.polishTranscript()
                        } else {
                            vm.finishAutoFlow(text: text)
                        }
                    }
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    vm.setActionError(message, recoveryActions: [.retryTranscribe])
                    vm.isTranscribing = false
                }
            }
        }
    }

    func copyTranscript() {
        guard !transcriptText.isEmpty else {
            setActionError("No transcript available to copy.", markFailure: false)
            return
        }
        TextInsertionService.copyToClipboard(transcriptText)
        clearActionError()
    }

    func pasteTranscript() {
        guard !transcriptText.isEmpty else {
            setActionError("No transcript available to paste.", markFailure: false)
            return
        }

        TextInsertionService.copyToClipboard(transcriptText)

        guard TextInsertionService.isAccessibilityTrusted() else {
            TextInsertionService.promptAccessibility()
            setActionError(
                "Copied to clipboard. Grant Accessibility access in System Settings to enable auto-paste.",
                recoveryActions: [.retryPaste]
            )
            return
        }

        clearActionError()
        onRequestDismiss?()

        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            try? TextInsertionService.simulatePaste()
        }
    }

    func toggleClipPlayback() {
        if isPlayingClip {
            stopClipPlayback()
        } else {
            guard !recordingPath.isEmpty else { return }
            do {
                let url = URL(fileURLWithPath: recordingPath)
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
                isPlayingClip = true
                let duration = audioPlayer?.duration ?? 0
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64((duration + 0.1) * 1_000_000_000))
                    guard let self, self.isPlayingClip else { return }
                    self.stopClipPlayback()
                }
            } catch {
                setActionError("Could not play clip: \(error.localizedDescription)")
            }
        }
    }

    func stopClipPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingClip = false
    }

    func clearTranscript() {
        transcriptText = ""
        transcriptMeta = ""
        polishedText = ""
        cleanupRecordingFile()
        stopTTS()
        setFlowStage(.idle, line: isRecordingActive ? "Recording live" : "Ready to record")
    }

    /// Remove the temp recording file to avoid /tmp accumulation.
    private func cleanupRecordingFile() {
        guard !recordingPath.isEmpty else { return }
        let path = recordingPath
        recordingPath = ""
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - TTS Proofread

    /// Speak the best available text (polished > transcript) aloud.
    func toggleTTS() {
        if isSpeakingTTS {
            stopTTS()
        } else {
            let text = polishedText.isEmpty ? transcriptText : polishedText
            guard !text.isEmpty else { return }
            tts.onStateChange = { [weak self] speaking in
                self?.isSpeakingTTS = speaking
            }
            tts.speak(text)
            isSpeakingTTS = true
        }
    }

    func stopTTS() {
        tts.stop()
        isSpeakingTTS = false
    }

    // MARK: - History

    func openHistory() {
        showHistory = true
        onRequestFocus?()
    }
    func closeHistory() { showHistory = false }

    // MARK: - LLM Polish

    func openSettings() {
        showSettings = true
        onRequestFocus?()
        Task { @MainActor in
            await self.refreshLLMRuntime()
        }
    }
    func closeSettings() { showSettings = false }

    func polishTranscript() {
        guard canPolish else { return }

        if LLMPolisher.shared.requiresAPIKey && LLMPolisher.shared.apiKey == nil {
            setActionError(
                "Enter your API key in Settings to enable polishing, or switch to a local model endpoint.",
                recoveryActions: [.openSettings]
            )
            showSettings = true
            return
        }

        isPolishing = true
        let cmdLabel = commandMode.activeCommand?.name ?? "Polishing"
        setFlowStage(.polishing, line: "\(cmdLabel) transcript")
        clearActionError()
        let text = transcriptText
        let dictionary = DictionaryManager.loadEntries()
        let activeCommand = commandMode.activeCommand
        let vm = self

        Task.detached(priority: .userInitiated) {
            do {
                if !LLMPolisher.shared.requiresAPIKey {
                    let probe = await LLMPolisher.shared.runtimeProbe()
                    guard probe.isReady else {
                        let message = probe.actionHint ?? probe.line
                        await MainActor.run {
                            vm.setActionError(message, recoveryActions: [.refreshRuntime, .openSettings])
                            vm.isPolishing = false
                            vm.showSettings = true
                            vm.llmLine = probe.line
                            vm.llmHint = probe.actionHint ?? ""
                        }
                        return
                    }
                }

                let polished = try await LLMPolisher.shared.polish(text: text, dictionary: dictionary, commandOverride: activeCommand)
                await MainActor.run {
                    vm.polishedText = polished
                    vm.isPolishing = false
                    vm.setFlowStage(.readyToPaste, line: "Polished text ready")
                    if vm.isAutoFlow {
                        vm.finishAutoFlow(text: polished)
                    }
                }
            } catch {
                await MainActor.run {
                    vm.setActionError(error.localizedDescription, recoveryActions: [.retryPolish])
                    vm.isPolishing = false
                }
            }
        }
    }

    func copyPolished() {
        guard !polishedText.isEmpty else { return }
        TextInsertionService.copyToClipboard(polishedText)
        clearActionError()
    }

    func pastePolished() {
        guard !polishedText.isEmpty else { return }

        TextInsertionService.copyToClipboard(polishedText)

        guard TextInsertionService.isAccessibilityTrusted() else {
            TextInsertionService.promptAccessibility()
            setActionError(
                "Copied to clipboard. Grant Accessibility access in System Settings to enable auto-paste.",
                recoveryActions: [.retryPaste]
            )
            return
        }

        clearActionError()
        onRequestDismiss?()

        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            try? TextInsertionService.simulatePaste()
        }
    }

    private func statusLine(name: String, path: String, available: Bool) -> String {
        let location = URL(fileURLWithPath: path).lastPathComponent
        return available ? "\(name) ready · \(location)" : "\(name) missing · \(location)"
    }

    private func setFlowStage(_ stage: FlowStage, line: String? = nil, hint: String = "") {
        flowStage = stage
        flowLine = line ?? stage.label
        flowHint = hint
        recordingLine = flowLine

        // Drive metrics tracking.
        switch stage {
        case .recording:
            metrics.beginSession()
            metrics.beginStage("recording")
        case .transcribing:
            metrics.beginStage("transcribing")
        case .polishing:
            metrics.beginStage("polishing")
        case .readyToPaste:
            metrics.endCurrentStage(outcome: .success)
            // Record successful session to history.
            if let summary = metrics.endSession(outcome: .success) {
                let text = polishedText.isEmpty ? transcriptText : polishedText
                history.record(
                    durationSec: summary.totalDuration,
                    textLength: text.count,
                    mode: isAutoFlow ? "auto" : "manual",
                    polished: !polishedText.isEmpty,
                    success: true
                )
            }
        case .failed:
            metrics.endCurrentStage(outcome: .failure)
            if let summary = metrics.endSession(outcome: .failure) {
                history.record(
                    durationSec: summary.totalDuration,
                    textLength: 0,
                    mode: isAutoFlow ? "auto" : "manual",
                    polished: false,
                    success: false
                )
            }
        case .idle:
            if metrics.currentSession != nil {
                _ = metrics.endSession(outcome: .success)
            }
        }
    }

    func performRecoveryAction(_ action: RecoveryAction) {
        switch action {
        case .refreshRuntime:
            refreshRuntime()
        case .openSettings:
            openSettings()
        case .retryTranscribe:
            transcribeLatestRecording()
        case .retryPolish:
            polishTranscript()
        case .retryPaste:
            if !polishedText.isEmpty {
                pastePolished()
            } else {
                pasteTranscript()
            }
        case .startRecording:
            startRecording()
        }
    }

    private func setActionError(
        _ message: String,
        recoveryActions: [RecoveryAction] = [],
        markFailure: Bool = true
    ) {
        actionError = Self.sanitizeErrorMessage(message)
        self.recoveryActions = recoveryActions
        if markFailure {
            setFlowStage(.failed, line: "Action failed")
        }
    }

    /// Strip internal file paths and C++ source references from error messages
    /// so users see a clean, actionable description.
    private static func sanitizeErrorMessage(_ message: String) -> String {
        var result = message
        // Strip sherpa-onnx / C++ source file paths (e.g. /Users/runner/work/.../file.cc:Function:123)
        let pathPattern = #"/[\w/.-]+\.(cc|cpp|h|c):[\w]+:\d+\s*"#
        if let regex = try? NSRegularExpression(pattern: pathPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearActionError() {
        actionError = ""
        recoveryActions = []
    }
}
