import Foundation

struct SpeechRuntimeStatus {
    let providerIdentifier: String
    let providerDisplayName: String
    let modelName: String?
    let helperPath: String
    let helperStatusLine: String
    let helperOriginLine: String
    let isHelperAvailable: Bool
    let supportDirectoryPath: String
    let configFilePath: String

    var summaryLine: String {
        isHelperAvailable
            ? "\(providerDisplayName) runtime ready"
            : "\(providerDisplayName) helper unavailable"
    }
}

@MainActor
enum SpeechRuntimeProbe {
    static func currentStatus() -> SpeechRuntimeStatus {
        let providerIdentifier = ConfigManager.shared.asrProvider
        let helperPath = AppPaths.coliHelperPath
        let isHelperAvailable = ColiTranscriber.isAvailable(at: helperPath)

        let providerDisplayName: String
        if providerIdentifier.lowercased().hasPrefix("coli") {
            providerDisplayName = "Coli"
        } else {
            providerDisplayName = providerIdentifier
        }

        return SpeechRuntimeStatus(
            providerIdentifier: providerIdentifier,
            providerDisplayName: providerDisplayName,
            modelName: configuredModelName(from: providerIdentifier),
            helperPath: helperPath,
            helperStatusLine: isHelperAvailable
                ? "Executable helper found"
                : "Helper missing or not executable",
            helperOriginLine: helperOriginLine(for: helperPath),
            isHelperAvailable: isHelperAvailable,
            supportDirectoryPath: AppPaths.appSupportDirectory.path,
            configFilePath: AppPaths.configFile.path
        )
    }

    private static func configuredModelName(from providerIdentifier: String) -> String? {
        let parts = providerIdentifier.split(separator: "-", maxSplits: 1).map(String.init)
        if parts.count == 2, !parts[1].isEmpty {
            return parts[1]
        }

        if providerIdentifier.lowercased().hasPrefix("coli") {
            return ColiTranscriber.defaultModel
        }

        return nil
    }

    private static func helperOriginLine(for helperPath: String) -> String {
        if ProcessInfo.processInfo.environment["VOICE_INPUT_HELPERS_DIR"] != nil {
            return "Resolved from VOICE_INPUT_HELPERS_DIR"
        }

        if helperPath.contains("/Contents/Helpers/") {
            return "Bundled with Murmur.app"
        }

        return "Resolved from system path search"
    }
}
