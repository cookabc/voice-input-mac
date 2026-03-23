import AppKit
import AVFoundation
import Foundation

@MainActor
final class ShellViewModel: ObservableObject {
    var onRequestDismiss: (() -> Void)?
    var onRequestQuit: (() -> Void)?
    var onRequestFocus: (() -> Void)?
    /// Called when an auto-flow cycle completes (after paste or on failure).
    var onAutoFlowComplete: (() -> Void)?
    /// Set by PanelController; called when the user picks a new shortcut in Settings.
    var onUpdateHotkey: ((NSEvent.ModifierFlags, UInt16) -> Void)?
    /// Human-readable hotkey string (e.g. "⌥Space"), kept in sync by PanelController.
    @Published var hotkeyDisplayString: String = ""

    @Published var title = "Voice Input"
    @Published var detail = "Checking the dictation engine…"
    @Published var runtimeBadge = "Checking"
    @Published var coliLine = "coli unresolved"
    @Published var recordingLine = "Idle"
    @Published var recordingPath = ""
    @Published var actionError = ""
    @Published var transcriptText = ""
    @Published var transcriptMeta = ""
    @Published var isTranscribing = false
    @Published var isPlayingClip = false
    @Published var liveTranscript = ""
    @Published var isPolishing = false
    @Published var polishedText = ""
    @Published var showSettings = false
    @Published var recordingElapsed = 0
    @Published var micLevel: Float = 0
    /// True while an auto-flow (hotkey-initiated) cycle is running.
    @Published var isAutoFlow: Bool = false
    /// True while the compact overlay pill is the active UI mode.
    @Published var compactMode: Bool = false
    /// Brief human-readable status shown in the compact pill.
    @Published var autoFlowStatus: String = ""
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?

    private let core = VoiceCoreService()

    var isReady: Bool { runtimeBadge == "Ready" }
    var isRecordingActive: Bool { recordingLine == "Recording live" }

    // MARK: - Hotkey / Auto-flow

    /// Called by `HotkeyManager` each time the global shortcut fires.
    /// First press → start recording; second press → stop + chain polish → paste.
    func handleHotkey() {
        if isRecordingActive {
            // Second press: stop and let the auto-chain do the rest.
            stopRecording()
        } else if canStartRecording {
            isAutoFlow = true
            compactMode = true
            autoFlowStatus = "Listening…"
            startRecording()
        }
    }

    private func finishAutoFlow(text: String) {
        guard !text.isEmpty else {
            isAutoFlow = false
            compactMode = false
            onAutoFlowComplete?()
            return
        }

        TextInsertionService.copyToClipboard(text)

        guard TextInsertionService.isAccessibilityTrusted() else {
            TextInsertionService.promptAccessibility()
            autoFlowStatus = "Copied (no Accessibility)"
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
        coliLine.contains("ready") ? "✓ coli" : "✗ coli"
    }

    var recordingTimeString: String {
        let m = recordingElapsed / 60
        let s = recordingElapsed % 60
        return String(format: "%d:%02d", m, s)
    }

    func refreshRuntime() {
        Task { @MainActor in
            // Await permissions so the recognizer is authorized before the first recording.
            await core.requestPermissions()

            let coliExists = core.checkColiAvailable()
            runtimeBadge = coliExists ? "Ready" : "Needs setup"

            if coliExists {
                title = "Ready to dictate"
                detail = "Record a clip, then transcribe and paste it into any app."
            } else {
                title = "Setup required"
                detail = "Install coli (@marswave/coli) to enable transcription."
            }

            coliLine = statusLine(name: "coli", path: AppPaths.coliHelperPath, available: coliExists)
            recordingLine = core.isRecording ? "Recording live" : "Ready to record"
            actionError = ""
        }
    }

    func startRecording() {
        guard canStartRecording else {
            actionError = isReady ? "Recording is already running." : "Runtime is not ready for recording yet."
            return
        }

        stopClipPlayback()

        do {
            let path = try core.startRecording()
            // Update recording state immediately — must happen before startLiveTranscription
            // so a live-ASR failure never leaves the UI in a zombie "Start failed" state.
            recordingPath = path
            recordingLine = "Recording live"
            actionError = ""
            transcriptText = ""
            transcriptMeta = ""
            liveTranscript = ""
            polishedText = ""
        } catch {
            actionError = error.localizedDescription
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
            actionError = "There is no active recording to stop."
            return
        }

        recordingTimer?.invalidate()
        recordingTimer = nil
        core.levelCallback = nil
        micLevel = 0
        core.stopRecording()
        recordingLine = "Recorded"
        actionError = ""
        if isAutoFlow { autoFlowStatus = "Transcribing…" }
        transcribeLatestRecording()
    }

    func transcribeLatestRecording() {
        guard canTranscribe else { return }

        isTranscribing = true
        actionError = ""
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
                    vm.actionError = ""
                    // Auto-flow: chain straight to polish if API key present, else paste raw.
                    if vm.isAutoFlow {
                        if LLMPolisher.shared.apiKey != nil && !text.isEmpty {
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
                    vm.actionError = message
                    vm.isTranscribing = false
                }
            }
        }
    }

    func copyTranscript() {
        guard !transcriptText.isEmpty else {
            actionError = "No transcript available to copy."
            return
        }
        TextInsertionService.copyToClipboard(transcriptText)
        actionError = ""
    }

    func pasteTranscript() {
        guard !transcriptText.isEmpty else {
            actionError = "No transcript available to paste."
            return
        }

        TextInsertionService.copyToClipboard(transcriptText)

        guard TextInsertionService.isAccessibilityTrusted() else {
            TextInsertionService.promptAccessibility()
            actionError = "Copied to clipboard. Grant Accessibility access in System Settings to enable auto-paste."
            return
        }

        actionError = ""
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
                actionError = "Could not play clip: \(error.localizedDescription)"
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
    }

    // MARK: - LLM Polish

    func openSettings() {
        showSettings = true
        onRequestFocus?()
    }
    func closeSettings() { showSettings = false }

    func polishTranscript() {
        guard canPolish else { return }

        if LLMPolisher.shared.apiKey == nil {
            actionError = "Enter your API key in Settings to enable polishing."
            showSettings = true
            return
        }

        isPolishing = true
        actionError = ""
        let text = transcriptText
        let dictionary = DictionaryManager.loadEntries()
        let vm = self

        Task.detached(priority: .userInitiated) {
            do {
                let polished = try await LLMPolisher.shared.polish(text: text, dictionary: dictionary)
                await MainActor.run {
                    vm.polishedText = polished
                    vm.isPolishing = false
                    if vm.isAutoFlow {
                        vm.finishAutoFlow(text: polished)
                    }
                }
            } catch {
                await MainActor.run {
                    vm.actionError = error.localizedDescription
                    vm.isPolishing = false
                }
            }
        }
    }

    func copyPolished() {
        guard !polishedText.isEmpty else { return }
        TextInsertionService.copyToClipboard(polishedText)
        actionError = ""
    }

    func pastePolished() {
        guard !polishedText.isEmpty else { return }

        TextInsertionService.copyToClipboard(polishedText)

        guard TextInsertionService.isAccessibilityTrusted() else {
            TextInsertionService.promptAccessibility()
            actionError = "Copied to clipboard. Grant Accessibility access in System Settings to enable auto-paste."
            return
        }

        actionError = ""
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
}
