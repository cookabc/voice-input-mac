import Foundation

enum AppPaths {
    static var appSupportDirectory: URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseDirectory.appendingPathComponent("Murmur", isDirectory: true)
    }

    static var legacySupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".murmur", isDirectory: true)
    }

    static var configFile: URL {
        appSupportDirectory.appendingPathComponent("config.json")
    }

    static var legacyConfigFile: URL {
        legacySupportDirectory.appendingPathComponent("config.json")
    }

    static var promptsDirectory: URL {
        appSupportDirectory.appendingPathComponent("prompts", isDirectory: true)
    }

    static var legacyPromptsDirectory: URL {
        legacySupportDirectory.appendingPathComponent("prompts", isDirectory: true)
    }

    static var systemPromptFile: URL {
        promptsDirectory.appendingPathComponent("system.txt")
    }

    static var userPromptFile: URL {
        promptsDirectory.appendingPathComponent("user.txt")
    }

    static var legacySystemPromptFile: URL {
        legacyPromptsDirectory.appendingPathComponent("system.txt")
    }

    static var legacyUserPromptFile: URL {
        legacyPromptsDirectory.appendingPathComponent("user.txt")
    }

    static var dictionaryFile: URL {
        appSupportDirectory.appendingPathComponent("dictionary.txt")
    }

    static var coliModelsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".coli", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    static var legacyDictionaryFile: URL {
        legacySupportDirectory.appendingPathComponent("dictionary.txt")
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
            let resourceBinaryPath = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent(name)
                .path
            if FileManager.default.fileExists(atPath: resourceBinaryPath) {
                return resourceBinaryPath
            }

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
