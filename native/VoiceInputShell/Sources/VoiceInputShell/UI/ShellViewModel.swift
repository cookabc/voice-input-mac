import AVFoundation
import Foundation

@MainActor
final class ShellViewModel: ObservableObject {
    var onRequestDismiss: (() -> Void)?

    @Published var title = "Voice Input"
    @Published var detail = "Checking the dictation engine…"
    @Published var rustVersion = "—"
    @Published var runtimeBadge = "Checking"
    @Published var ffmpegLine = "ffmpeg unresolved"
    @Published var coliLine = "coli unresolved"
    @Published var recordingLine = "Idle"
    @Published var recordingPath = ""
    @Published var actionError = ""
    @Published var transcriptText = ""
    @Published var transcriptMeta = ""
    @Published var diagnosticsExpanded = false
    @Published var isTranscribing = false
    @Published var isPlayingClip = false
    private var audioPlayer: AVAudioPlayer?

    var isReady: Bool {
        runtimeBadge == "Ready"
    }

    var isRecordingActive: Bool {
        recordingLine == "Recording live"
    }

    var primaryActionTitle: String {
        isRecordingActive ? "Stop recording" : "Start recording"
    }

    var primaryActionSubtitle: String {
        if isRecordingActive {
            return "Capture is live. Stop when you're ready to transcribe."
        }

        return isReady ? "Record a short clip, then transcribe and paste it." : "Engine isn’t ready yet — click Refresh to retry."
    }

    var canStartRecording: Bool {
        isReady && !isRecordingActive
    }

    var canStopRecording: Bool {
        isRecordingActive
    }

    var canTranscribe: Bool {
        !recordingPath.isEmpty && !isRecordingActive && !isTranscribing
    }

    var canPasteTranscript: Bool {
        !transcriptText.isEmpty
    }

    var diagnosticsSummary: String {
        "\(runtimeBadge) · \(ffmpegLine) · \(coliLine)"
    }

    func refreshRuntime() {
        do {
            let bridge = try RustCoreBridge.bridge()
            let summary = try bridge.runtimeSummary()
            let recording = try bridge.isRecording()
            rustVersion = bridge.version()
            runtimeBadge = summary.ffmpegExists && summary.coliExists ? "Ready" : "Needs setup"
            let missingTools = (!summary.ffmpegExists ? ["ffmpeg"] : []) + (!summary.coliExists ? ["coli"] : [])
            if missingTools.isEmpty {
                title = "Ready to dictate"
                detail = "Record a clip, then transcribe and paste it into any app."
            } else {
                title = "Setup required"
                let toolList = missingTools.joined(separator: " and ")
                detail = "Install \(toolList) to enable dictation, then click Refresh."
            }
            ffmpegLine = statusLine(name: "ffmpeg", path: summary.ffmpegPath, available: summary.ffmpegExists)
            coliLine = statusLine(name: "coli", path: summary.coliPath, available: summary.coliExists)
            recordingLine = recording ? "Recording live" : "Ready to record"
            actionError = ""
        } catch {
            runtimeBadge = "Offline"
            title = "Engine unavailable"
            detail = error.localizedDescription
            rustVersion = "—"
            ffmpegLine = "ffmpeg unresolved"
            coliLine = "coli unresolved"
            recordingLine = "Unavailable"
            transcriptText = ""
            transcriptMeta = ""
        }
    }

    func startRecording() {
        guard canStartRecording else {
            actionError = isReady ? "Recording is already running." : "Runtime is not ready for recording yet."
            return
        }

        stopClipPlayback()

        do {
            let path = try RustCoreBridge.bridge().startRecording()
            recordingPath = path
            recordingLine = "Recording live"
            actionError = ""
            transcriptText = ""
            transcriptMeta = ""
        } catch {
            actionError = error.localizedDescription
            recordingLine = "Start failed"
        }
    }

    func stopRecording() {
        guard canStopRecording else {
            actionError = "There is no active recording to stop."
            return
        }

        do {
            try RustCoreBridge.bridge().stopRecording()
            recordingLine = "Recorded"
            actionError = ""
        } catch {
            actionError = error.localizedDescription
            recordingLine = "Stop failed"
        }
    }

    func transcribeLatestRecording() {
        guard canTranscribe else { return }

        isTranscribing = true
        actionError = ""
        let path = recordingPath
        let vm = self   // strong let — keeps vm alive for the duration of the task

        Task.detached(priority: .userInitiated) {
            do {
                let result = try RustCoreBridge.bridge().transcribeAudio(at: path)
                let text = result.text
                var metaParts = [String]()
                if let lang = result.lang, !lang.isEmpty {
                    metaParts.append("lang: \(lang)")
                }
                if let duration = result.duration {
                    metaParts.append(String(format: "audio: %.1fs", duration))
                }
                let meta = metaParts.joined(separator: "  |  ")
                await MainActor.run {
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
    }

    func toggleDiagnostics() {
        diagnosticsExpanded.toggle()
    }

    private func statusLine(name: String, path: String?, available: Bool) -> String {
        let location = path.flatMap { URL(fileURLWithPath: $0).lastPathComponent.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent } ?? "not found"
        return available ? "\(name) ready · \(location)" : "\(name) missing · \(location)"
    }
}
