import AppKit
import AVFoundation
import Foundation

@MainActor
final class ShellViewModel: ObservableObject {
    var onRequestDismiss: (() -> Void)?
    var onRequestQuit: (() -> Void)?

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
    private var audioPlayer: AVAudioPlayer?

    private let core = VoiceCoreService()

    var isReady: Bool { runtimeBadge == "Ready" }
    var isRecordingActive: Bool { recordingLine == "Recording live" }
    var canStartRecording: Bool { isReady && !isRecordingActive }
    var canStopRecording: Bool { isRecordingActive }
    var canTranscribe: Bool { !recordingPath.isEmpty && !isRecordingActive && !isTranscribing }
    var canPasteTranscript: Bool { !transcriptText.isEmpty }
    var canPolish: Bool { !transcriptText.isEmpty && !isPolishing && !isTranscribing }

    var statusFooter: String {
        coliLine.contains("ready") ? "✓ coli" : "✗ coli"
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

        // Live transcription is best-effort — recording continues even if unavailable.
        do {
            try core.startLiveTranscription { [weak self] partial in
                Task { @MainActor [weak self] in
                    self?.liveTranscript = partial
                }
            }
        } catch {
            // Speech recognition unavailable (e.g. not authorized yet); coli covers final ASR.
        }
    }

    func stopRecording() {
        guard canStopRecording else {
            actionError = "There is no active recording to stop."
            return
        }

        core.stopRecording()
        core.stopLiveTranscription()
        recordingLine = "Recorded"
        actionError = ""
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
                if let lang = result.lang, !lang.isEmpty { metaParts.append("lang: \(lang)") }
                if let dur = result.duration { metaParts.append(String(format: "audio: %.1fs", dur)) }
                let meta = metaParts.joined(separator: "  |  ")
                await MainActor.run {
                    vm.liveTranscript = ""
                    vm.transcriptText = text
                    vm.transcriptMeta = meta
                    vm.isTranscribing = false
                    vm.actionError = ""
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

    func polishTranscript() {
        guard canPolish else { return }

        if LLMPolisher.shared.apiKey == nil {
            promptForApiKey { [weak self] in self?.polishTranscript() }
            return
        }

        isPolishing = true
        actionError = ""
        let text = transcriptText
        let vm = self

        Task.detached(priority: .userInitiated) {
            do {
                let polished = try await LLMPolisher.shared.polish(text: text)
                await MainActor.run {
                    vm.polishedText = polished
                    vm.isPolishing = false
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

    private func promptForApiKey(completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "OpenAI API Key"
        alert.informativeText = "Enter your API key to enable transcript polishing. It is stored locally and never sent anywhere except your chosen endpoint."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = "sk-…"
        field.usesSingleLineMode = true
        field.stringValue = LLMPolisher.shared.apiKey ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        LLMPolisher.shared.saveApiKey(key)
        completion()
    }

    private func statusLine(name: String, path: String, available: Bool) -> String {
        let location = URL(fileURLWithPath: path).lastPathComponent
        return available ? "\(name) ready · \(location)" : "\(name) missing · \(location)"
    }
}
