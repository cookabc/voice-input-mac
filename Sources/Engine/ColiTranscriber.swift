import Foundation

struct TranscriptionResult {
    let text: String
    let lang: String?
    let duration: Double?
}

enum ColiTranscriberError: Error, LocalizedError {
    case audioFileNotFound(String)
    case processFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .audioFileNotFound(let p): return "Audio file not found: \(p)"
        case .processFailed(let m):    return "Transcription failed: \(m)"
        case .parseError(let r):       return "Unexpected transcription response: \(r)"
        }
    }
}

actor ColiTranscriber {
    static let defaultModel = "sensevoice"

    private struct Response: Decodable {
        let text: String
        let text_clean: String?
        let lang: String?
        let duration: Double?
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    func transcribe(
        filePath: String,
        coliPath: String,
        model: String = ColiTranscriber.defaultModel,
        polish: Bool = true
    ) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ColiTranscriberError.audioFileNotFound(filePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: coliPath)
        process.arguments = ["asr", "-j", "--model", model, filePath]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let killTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            if process.isRunning { process.terminate() }
        }

        process.waitUntilExit()
        killTask.cancel()

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ColiTranscriberError.processFailed(
                msg.isEmpty ? "exit code \(process.terminationStatus)" : msg
            )
        }

        let decoder = JSONDecoder()
        if let r = try? decoder.decode(Response.self, from: outData) {
            return TranscriptionResult(
                text: polish ? (r.text_clean ?? r.text) : r.text,
                lang: r.lang,
                duration: r.duration
            )
        } else if let e = try? decoder.decode(ErrorResponse.self, from: outData) {
            throw ColiTranscriberError.processFailed(e.error)
        } else {
            let raw = String(data: outData, encoding: .utf8) ?? ""
            throw ColiTranscriberError.parseError(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func isAvailable(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
