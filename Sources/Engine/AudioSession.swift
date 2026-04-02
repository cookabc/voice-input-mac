import AVFoundation
import Foundation

enum AudioSessionError: Error, LocalizedError {
    case alreadyRecording
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:         return "A recording is already in progress."
        case .engineStartFailed(let m): return "Could not start audio engine: \(m)"
        }
    }
}

final class AudioSession {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private(set) var isRecording = false
    private(set) var recordingPath = ""

    // Set before startRecording(); called from the audio tap thread for each buffer.
    var bufferSink: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    // Called from the tap thread with a 0–1 normalized mic level (dB-based).
    var levelSink: ((Float) -> Void)?

    var recordingFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func startRecording() throws -> String {
        guard !isRecording else { throw AudioSessionError.alreadyRecording }

        let recordingURL = makeRecordingURL()
        let path = recordingURL.path

        let fmt = engine.inputNode.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(
            forWriting: recordingURL,
            settings: fmt.settings
        )
        recordingPath = path

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, time in
            guard let self else { return }
            try? self.audioFile?.write(from: buf)
            self.bufferSink?(buf, time)
            // Compute RMS → dB-normalised 0–1 level and forward.
            if let data = buf.floatChannelData?[0] {
                let count = Int(buf.frameLength)
                var sum: Float = 0
                for i in 0..<count { let s = data[i]; sum += s * s }
                let rms = count > 0 ? sqrt(sum / Float(count)) : 0
                let db = 20.0 * log10(max(Double(rms), 1e-5))
                let level = Float(max(0, min(1, (db + 50.0) / 50.0)))
                self.levelSink?(level)
            }
        }

        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            audioFile = nil
            try? FileManager.default.removeItem(at: recordingURL)
            recordingPath = ""
            throw AudioSessionError.engineStartFailed(error.localizedDescription)
        }

        isRecording = true
        return path
    }

    func stopRecording() {
        guard isRecording else { return }
        // removeTap must happen first — guarantees no more bufferSink calls after this returns.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRecording = false
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-recording-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }
}
