import Darwin
import Foundation

typealias VoiceCoreVersionFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
typealias VoiceCoreConfigureToolsFn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool
typealias VoiceCoreSmokeStatusFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
typealias VoiceCoreLastErrorFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
typealias VoiceCoreStartRecordingFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
typealias VoiceCoreStopRecordingFn = @convention(c) () -> Bool
typealias VoiceCoreIsRecordingFn = @convention(c) () -> Bool
typealias VoiceCoreStringFreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

struct RustSmokeStatus: Decodable {
    let name: String
    let version: String
    let ffmpegPath: String?
    let coliPath: String?
    let ffmpegExists: Bool
    let coliExists: Bool
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
    static let shared = RustCoreBridge()

    private let handle: UnsafeMutableRawPointer
    private let versionFn: VoiceCoreVersionFn
    private let configureToolsFn: VoiceCoreConfigureToolsFn
    private let smokeStatusFn: VoiceCoreSmokeStatusFn
    private let lastErrorFn: VoiceCoreLastErrorFn
    private let startRecordingFn: VoiceCoreStartRecordingFn
    private let stopRecordingFn: VoiceCoreStopRecordingFn
    private let isRecordingFn: VoiceCoreIsRecordingFn
    private let stringFreeFn: VoiceCoreStringFreeFn

    private init() {
        let libraryPath = AppPaths.rustCoreLibraryPath
        guard let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            fatalError("Failed to load Rust core: \(libraryPath)")
        }

        self.handle = handle
        versionFn = RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_version")
        configureToolsFn = RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_configure_tools")
        smokeStatusFn = RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_smoke_status_json")
        lastErrorFn = RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_last_error_message")
        startRecordingFn = RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_start_recording")
        stopRecordingFn = RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_stop_recording")
        isRecordingFn = RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_is_recording")
        stringFreeFn = RustCoreBridge.loadSymbol(handle: handle, name: "voice_input_core_string_free")
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
        return try JSONDecoder().decode(RustSmokeStatus.self, from: data)
    }

    func version() -> String {
        guard let raw = versionFn() else {
            return "unknown"
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

    private static func loadSymbol<T>(handle: UnsafeMutableRawPointer, name: String) -> T {
        guard let symbol = dlsym(handle, name) else {
            fatalError("Missing Rust core symbol: \(name)")
        }

        return unsafeBitCast(symbol, to: T.self)
    }
}
