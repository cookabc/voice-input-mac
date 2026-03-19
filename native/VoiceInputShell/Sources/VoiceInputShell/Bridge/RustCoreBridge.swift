import Darwin
import Foundation

typealias VoiceCoreVersionFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
typealias VoiceCoreConfigureToolsFn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool
typealias VoiceCoreSmokeStatusFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
typealias VoiceCoreLastErrorFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
typealias VoiceCoreStartRecordingFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
typealias VoiceCoreStopRecordingFn = @convention(c) () -> Bool
typealias VoiceCoreIsRecordingFn = @convention(c) () -> Bool
typealias VoiceCoreTranscribeAudioFn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, Bool) -> UnsafeMutablePointer<CChar>?
typealias VoiceCoreStringFreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
typealias VoiceCoreStartLiveASRFn = @convention(c) () -> Bool
typealias VoiceCoreStopLiveASRFn = @convention(c) () -> Bool
typealias VoiceCoreGetPartialTranscriptFn = @convention(c) () -> UnsafeMutablePointer<CChar>?

struct RustSmokeStatus: Decodable {
    let name: String
    let version: String
    let ffmpegPath: String?
    let coliPath: String?
    let ffmpegExists: Bool
    let coliExists: Bool
}

struct RustTranscriptionResult: Decodable {
    let text: String
    let lang: String?
    let duration: Double?
}

enum RustCoreBridgeError: Error {
    case libraryNotFound(String)
    case symbolMissing(String)
    case callFailed(String)
}

extension RustCoreBridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .libraryNotFound(let path):
            return "Rust core library not found at \(path)"
        case .symbolMissing(let symbol):
            return "Rust core symbol missing: \(symbol)"
        case .callFailed(let message):
            return message
        }
    }
}

final class RustCoreBridge {
    private static let _result: Result<RustCoreBridge, Error> = {
        Result { try RustCoreBridge() }
    }()

    static func bridge() throws -> RustCoreBridge {
        try _result.get()
    }

    private let handle: UnsafeMutableRawPointer
    private let versionFn: VoiceCoreVersionFn
    private let configureToolsFn: VoiceCoreConfigureToolsFn
    private let smokeStatusFn: VoiceCoreSmokeStatusFn
    private let lastErrorFn: VoiceCoreLastErrorFn
    private let startRecordingFn: VoiceCoreStartRecordingFn
    private let stopRecordingFn: VoiceCoreStopRecordingFn
    private let isRecordingFn: VoiceCoreIsRecordingFn
    private let transcribeAudioFn: VoiceCoreTranscribeAudioFn
    private let stringFreeFn: VoiceCoreStringFreeFn
    private let startLiveTranscriptionFn: VoiceCoreStartLiveASRFn
    private let stopLiveTranscriptionFn: VoiceCoreStopLiveASRFn
    private let getPartialTranscriptFn: VoiceCoreGetPartialTranscriptFn

    private init() throws {
        let libraryPath = AppPaths.rustCoreLibraryPath
        guard let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            let dlErr = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw RustCoreBridgeError.libraryNotFound("\(libraryPath) — \(dlErr)")
        }

        self.handle = handle
        versionFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_version")
        configureToolsFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_configure_tools")
        smokeStatusFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_smoke_status_json")
        lastErrorFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_last_error_message")
        startRecordingFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_start_recording")
        stopRecordingFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_stop_recording")
        isRecordingFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_is_recording")
        transcribeAudioFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_transcribe_audio")
        stringFreeFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_string_free")
        startLiveTranscriptionFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_start_live_transcription")
        stopLiveTranscriptionFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_stop_live_transcription")
        getPartialTranscriptFn = try RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_get_partial_transcript")
    }

    deinit {
        dlclose(handle)
    }

    func runtimeSummary() throws -> RustSmokeStatus {
        try configureHelperPaths()

        guard let raw = smokeStatusFn() else {
            throw RustCoreBridgeError.callFailed("Rust core returned no smoke status")
        }

        defer { stringFreeFn(raw) }

        let data = Data(bytes: raw, count: strlen(raw))
    return try Self.makeDecoder().decode(RustSmokeStatus.self, from: data)
    }

    func version() -> String {
        guard let raw = versionFn() else {
            return "—"
        }

        defer { stringFreeFn(raw) }
        return String(cString: raw)
    }

    func isRecording() throws -> Bool {
        try configureHelperPaths()
        return isRecordingFn()
    }

    func startRecording() throws -> String {
        try configureHelperPaths()

        guard let raw = startRecordingFn() else {
            throw RustCoreBridgeError.callFailed(lastErrorMessage())
        }

        defer { stringFreeFn(raw) }
        return String(cString: raw)
    }

    func stopRecording() throws {
        try configureHelperPaths()

        guard stopRecordingFn() else {
            throw RustCoreBridgeError.callFailed(lastErrorMessage())
        }
    }

    func transcribeAudio(at audioPath: String, model: String = "sensevoice", polish: Bool = true) throws -> RustTranscriptionResult {
        try configureHelperPaths()

        return try audioPath.withCString { audioPathPtr in
            try model.withCString { modelPtr in
                guard let raw = transcribeAudioFn(audioPathPtr, modelPtr, polish) else {
                    throw RustCoreBridgeError.callFailed(lastErrorMessage())
                }

                defer { stringFreeFn(raw) }
                let data = Data(bytes: raw, count: strlen(raw))
                return try Self.makeDecoder().decode(RustTranscriptionResult.self, from: data)
            }
        }
    }

    func startLiveTranscription() throws {
        try configureHelperPaths()
        guard startLiveTranscriptionFn() else {
            throw RustCoreBridgeError.callFailed(lastErrorMessage())
        }
    }

    func stopLiveTranscription() throws {
        try configureHelperPaths()
        guard stopLiveTranscriptionFn() else {
            throw RustCoreBridgeError.callFailed(lastErrorMessage())
        }
    }

    func getPartialTranscript() -> String {
        // configureHelperPaths already called during startLiveTranscription;
        // skip it here to keep polling fast.
        guard let raw = getPartialTranscriptFn() else { return "" }
        defer { stringFreeFn(raw) }
        return String(cString: raw)
    }

    private func configureHelperPaths() throws {
        let configured = AppPaths.ffmpegHelperPath.withCString { ffmpegPtr in
            AppPaths.coliHelperPath.withCString { coliPtr in
                configureToolsFn(ffmpegPtr, coliPtr)
            }
        }

        guard configured else {
            throw RustCoreBridgeError.callFailed("Failed to configure helper binary paths")
        }
    }

    private func lastErrorMessage() -> String {
        guard let raw = lastErrorFn() else {
            return "Rust core call failed"
        }

        defer { stringFreeFn(raw) }

        let message = String(cString: raw)
        return message.isEmpty ? "Rust core call failed" : message
    }

    private static func loadSymbol<T>(handle: UnsafeMutableRawPointer, name: String) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw RustCoreBridgeError.symbolMissing(name)
        }

        return unsafeBitCast(symbol, to: T.self)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
