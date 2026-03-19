import Foundation

enum AppPaths {
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
