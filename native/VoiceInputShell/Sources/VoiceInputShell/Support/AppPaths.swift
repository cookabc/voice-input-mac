import Foundation

enum AppPaths {
    static var rustCoreLibraryPath: String {
        if let override = ProcessInfo.processInfo.environment["VOICE_INPUT_CORE_DYLIB"],
           FileManager.default.fileExists(atPath: override) {
            return override
        }

        if let privateFrameworksPath = Bundle.main.privateFrameworksPath {
            let bundled = URL(fileURLWithPath: privateFrameworksPath)
                .appendingPathComponent("libvoice_input_core.dylib")
                .path
            if FileManager.default.fileExists(atPath: bundled) {
                return bundled
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let executableDirectory = executableURL.deletingLastPathComponent()
        let candidates = [
            executableDirectory.appendingPathComponent("../../../../../voice-core/target/debug/libvoice_input_core.dylib"),
            executableDirectory.appendingPathComponent("../../../voice-core/target/debug/libvoice_input_core.dylib"),
            cwd.appendingPathComponent("../../voice-core/target/debug/libvoice_input_core.dylib"),
            cwd.appendingPathComponent("voice-core/target/debug/libvoice_input_core.dylib"),
        ]

        if let match = candidates
            .map({ $0.standardizedFileURL.path })
            .first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return match
        }

        return candidates[0].standardizedFileURL.path
    }

    static var ffmpegHelperPath: String {
        helperBinaryPath(named: "ffmpeg")
    }

    static var coliHelperPath: String {
        helperBinaryPath(named: "coli")
    }

    private static func helperBinaryPath(named name: String) -> String {
        if let helpersOverride = ProcessInfo.processInfo.environment["VOICE_INPUT_HELPERS_DIR"] {
            let overridePath = URL(fileURLWithPath: helpersOverride)
                .appendingPathComponent(name)
                .path
            if FileManager.default.fileExists(atPath: overridePath) {
                return overridePath
            }
        }

        if let resourcePath = Bundle.main.resourcePath {
            let helperPath = URL(fileURLWithPath: resourcePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Helpers")
                .appendingPathComponent(name)
                .path
            if FileManager.default.fileExists(atPath: helperPath) {
                return helperPath
            }
        }

        let fallbackCandidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]

        return fallbackCandidates.first(where: { FileManager.default.fileExists(atPath: $0) })
            ?? fallbackCandidates[0]
    }
}
