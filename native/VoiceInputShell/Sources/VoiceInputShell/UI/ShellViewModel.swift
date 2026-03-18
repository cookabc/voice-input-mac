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
        }
    }

    func startRecording() {
        do {
            let path = try RustCoreBridge.shared.startRecording()
            recordingPath = path
            recordingLine = "Recording"
            actionError = ""
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
}
