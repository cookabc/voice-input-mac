import Foundation

@MainActor
final class ShellViewModel: ObservableObject {
    @Published var title = "Swift shell ready"
    @Published var detail = "The native menu bar shell is live. Load the Rust core to verify bundling paths."
    @Published var rustVersion = "unknown"
    @Published var ffmpegLine = "ffmpeg: unresolved"
    @Published var coliLine = "coli: unresolved"
    @Published var recordingLine = "Idle"
    @Published var recordingPath = ""
    @Published var actionError = ""
    @Published var transcriptText = ""
    @Published var transcriptMeta = ""

    func refreshRuntime() {
        do {
            let bridge = RustCoreBridge.shared
            let summary = try bridge.runtimeSummary()
            let recording = try bridge.isRecording()
            rustVersion = bridge.version()
            title = "Rust core connected"
            detail = "The Swift shell loaded the Rust core, configured bundled helper paths, and can now drive recording directly through the shared backend."
            ffmpegLine = "ffmpeg: \(summary.ffmpegPath ?? "missing") [\(summary.ffmpegExists ? "found" : "not found")]"
            coliLine = "coli: \(summary.coliPath ?? "missing") [\(summary.coliExists ? "found" : "not found")]"
            recordingLine = recording ? "Recording" : "Idle"
            actionError = ""
        } catch {
            title = "Rust core unavailable"
            detail = error.localizedDescription
            ffmpegLine = "ffmpeg: unresolved"
            coliLine = "coli: unresolved"
            recordingLine = "Unavailable"
            transcriptMeta = ""
        }
    }

    func startRecording() {
        do {
            let path = try RustCoreBridge.shared.startRecording()
            recordingPath = path
            recordingLine = "Recording"
            actionError = ""
            transcriptText = ""
            transcriptMeta = ""
            detail = "Recording from the menu bar shell through the shared Rust core. Stop recording to flush the wav file for the next ASR step."
        } catch {
            actionError = error.localizedDescription
            recordingLine = "Start failed"
        }
    }

    func stopRecording() {
        do {
            try RustCoreBridge.shared.stopRecording()
            recordingLine = "Stopped"
            actionError = ""
            if !recordingPath.isEmpty {
                detail = "Recording finished. Latest wav file: \(recordingPath)"
            }
        } catch {
            actionError = error.localizedDescription
            recordingLine = "Stop failed"
        }
    }

    func transcribeLatestRecording() {
        guard !recordingPath.isEmpty else {
            actionError = "No completed recording available to transcribe yet."
            return
        }

        do {
            let result = try RustCoreBridge.shared.transcribeAudio(at: recordingPath)
            transcriptText = result.text

            var metaParts = [String]()
            if let lang = result.lang, !lang.isEmpty {
                metaParts.append("lang: \(lang)")
            }
            if let duration = result.duration {
                metaParts.append(String(format: "audio: %.1fs", duration))
            }

            transcriptMeta = metaParts.joined(separator: "  |  ")
            actionError = ""
            detail = "Transcription completed through the shared Rust core."
        } catch {
            actionError = error.localizedDescription
        }
    }

    func copyTranscript() {
        guard !transcriptText.isEmpty else {
            actionError = "No transcript available to copy."
            return
        }

        TextInsertionService.copyToClipboard(transcriptText)
        actionError = ""
        detail = "Transcript copied to the clipboard."
    }

    func pasteTranscript() {
        guard !transcriptText.isEmpty else {
            actionError = "No transcript available to paste."
            return
        }

        do {
            try TextInsertionService.pasteToFrontmostApp(transcriptText)
            actionError = ""
            detail = "Transcript pasted into the frontmost app."
        } catch {
            actionError = error.localizedDescription
        }
    }
}
