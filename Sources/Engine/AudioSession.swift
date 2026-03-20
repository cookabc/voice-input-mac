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

    var recordingFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func startRecording() throws -> String {
        guard !isRecording else { throw AudioSessionError.alreadyRecording }

        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let path = "/tmp/voice_\(ts).wav"

        let fmt = engine.inputNode.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(
            forWriting: URL(fileURLWithPath: path),
            settings: fmt.settings
        )
        recordingPath = path

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, time in
            guard let self else { return }
            try? self.audioFile?.write(from: buf)
            self.bufferSink?(buf, time)
        }

        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            audioFile = nil
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
}
