import AVFoundation
import Foundation

@MainActor
final class VoiceCoreService {
    private let session = AudioSession()
    private let liveSpeech = LiveSpeechRecognizer()
    private let transcriber = ColiTranscriber()

    var isRecording: Bool { session.isRecording }

    func requestPermissions() async {
        await LiveSpeechRecognizer.requestAuthorization()
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    func checkColiAvailable() -> Bool {
        ColiTranscriber.isAvailable(at: AppPaths.coliHelperPath)
    }

    func startRecording() throws -> String {
        // Capture liveSpeech directly so the tap closure doesn't need to hop through
        // self (which is @MainActor-isolated).
        let ls = liveSpeech
        session.bufferSink = { buf, time in
            ls.appendBuffer(buf, at: time)
        }
        return try session.startRecording()
    }

    func stopRecording() {
        // removeTap() fires inside stopRecording() — guaranteed no more bufferSink
        // calls arrive after this returns, so stopLiveTranscription() is safe next.
        session.stopRecording()
    }

    var recordingFormat: AVAudioFormat { session.recordingFormat }

    func startLiveTranscription(onPartial: @escaping (String) -> Void) throws {
        liveSpeech.onPartialResult = onPartial
        try liveSpeech.start()
    }

    func stopLiveTranscription() {
        liveSpeech.stop()
    }

    func transcribeAudio(at path: String) async throws -> TranscriptionResult {
        try await transcriber.transcribe(filePath: path, coliPath: AppPaths.coliHelperPath)
    }
}
