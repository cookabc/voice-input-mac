import Foundation
import Observation

enum SpeechModelIdentifier: String, CaseIterable, Identifiable {
    case sensevoice
    case whisper

    var id: String { rawValue }

    var providerIdentifier: String {
        "coli-\(rawValue)"
    }

    var displayName: String {
        switch self {
        case .sensevoice:
            return "sensevoice-small"
        case .whisper:
            return "whisper-tiny.en"
        }
    }

    var summary: String {
        switch self {
        case .sensevoice:
            return "Default multilingual ASR for Chinese, English, Japanese, Korean, and Cantonese."
        case .whisper:
            return "English-focused fallback model based on Whisper tiny.en."
        }
    }

    var supportedLanguages: String {
        switch self {
        case .sensevoice:
            return "Chinese, English, Japanese, Korean, Cantonese"
        case .whisper:
            return "English"
        }
    }

    var modelDirectoryName: String {
        switch self {
        case .sensevoice:
            return "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
        case .whisper:
            return "sherpa-onnx-whisper-tiny.en"
        }
    }

    var requiredFileName: String {
        switch self {
        case .sensevoice:
            return "model.int8.onnx"
        case .whisper:
            return "tiny.en-encoder.int8.onnx"
        }
    }

    var downloadURL: URL {
        switch self {
        case .sensevoice:
            return URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2")!
        case .whisper:
            return URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2")!
        }
    }

    init?(providerIdentifier: String) {
        guard providerIdentifier.hasPrefix("coli-") else { return nil }
        self.init(rawValue: String(providerIdentifier.dropFirst(5)))
    }
}

struct SpeechModelState: Identifiable, Equatable {
    let id: SpeechModelIdentifier
    let displayName: String
    let summary: String
    let supportedLanguages: String
    let installPath: String
    let isInstalled: Bool
    let isSelected: Bool
}

@MainActor
@Observable
final class ModelManager {
    var models: [SpeechModelState] = []
    var activeDownloadModel: SpeechModelIdentifier?
    var downloadProgress: Double?
    var statusMessage: String = ""

    private let configManager: any ConfigManaging

    init(configManager: any ConfigManaging = ConfigManager.shared) {
        self.configManager = configManager
        refresh()
    }

    var modelsDirectoryPath: String {
        AppPaths.coliModelsDirectory.path
    }

    func refresh() {
        let selectedModel = SpeechModelIdentifier(providerIdentifier: configManager.asrProvider)
        models = SpeechModelIdentifier.allCases.map { identifier in
            SpeechModelState(
                id: identifier,
                displayName: identifier.displayName,
                summary: identifier.summary,
                supportedLanguages: identifier.supportedLanguages,
                installPath: installDirectory(for: identifier).path,
                isInstalled: isInstalled(identifier),
                isSelected: selectedModel == identifier
            )
        }
    }

    func selectModel(_ identifier: SpeechModelIdentifier) {
        guard isInstalled(identifier) else {
            statusMessage = "Install \(identifier.displayName) before switching to it."
            refresh()
            return
        }

        configManager.saveASRProvider(identifier.providerIdentifier)
        statusMessage = "Using \(identifier.displayName) for final transcription."
        refresh()
    }

    func installModel(_ identifier: SpeechModelIdentifier, selectAfterInstall: Bool = true) async {
        guard activeDownloadModel == nil else { return }

        if isInstalled(identifier) {
            if selectAfterInstall {
                selectModel(identifier)
            } else {
                statusMessage = "\(identifier.displayName) is already installed."
                refresh()
            }
            return
        }

        activeDownloadModel = identifier
        downloadProgress = 0
        statusMessage = "Downloading \(identifier.displayName)…"

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(identifier.modelDirectoryName)
            .appendingPathExtension("tar.bz2")

        do {
            try FileManager.default.createDirectory(
                at: AppPaths.coliModelsDirectory,
                withIntermediateDirectories: true
            )

            try await Self.downloadArchive(
                from: identifier.downloadURL,
                to: archiveURL,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }
            )

            statusMessage = "Extracting \(identifier.displayName)…"
            downloadProgress = nil
            try await Self.extractArchive(at: archiveURL, into: AppPaths.coliModelsDirectory)
            try? FileManager.default.removeItem(at: archiveURL)

            if selectAfterInstall {
                configManager.saveASRProvider(identifier.providerIdentifier)
            }

            statusMessage = "\(identifier.displayName) is ready."
            refresh()
        } catch {
            statusMessage = "Failed to install \(identifier.displayName): \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: archiveURL)
            refresh()
        }

        activeDownloadModel = nil
        downloadProgress = nil
    }

    private func installDirectory(for identifier: SpeechModelIdentifier) -> URL {
        AppPaths.coliModelsDirectory.appendingPathComponent(identifier.modelDirectoryName, isDirectory: true)
    }

    private func isInstalled(_ identifier: SpeechModelIdentifier) -> Bool {
        let modelDirectory = installDirectory(for: identifier)
        let checkFile = modelDirectory.appendingPathComponent(identifier.requiredFileName)
        return FileManager.default.fileExists(atPath: checkFile.path)
    }

    private static func extractArchive(at archiveURL: URL, into directory: URL) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["xjf", archiveURL.path, "-C", directory.path]

            let stderr = Pipe()
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "tar exited with code \(process.terminationStatus)"
                throw ModelInstallError.extractionFailed(message)
            }
        }.value
    }

    private static func downloadArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: sourceURL)
        let expectedLength = max(response.expectedContentLength, 0)

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? handle.close()
        }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var receivedLength: Int64 = 0

        for try await byte in bytes {
            buffer.append(byte)
            receivedLength += 1

            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)

                if expectedLength > 0 {
                    progressHandler(min(1, Double(receivedLength) / Double(expectedLength)))
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }

        if expectedLength > 0 {
            progressHandler(1)
        }
    }
}

enum ModelInstallError: LocalizedError {
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let message):
            return message
        }
    }
}